<#
.SYNOPSIS
Construye la imagen, la publica en ECR y actualiza el contenedor de EC2 vía SSM.

.PARAMETER ImageTag
Etiqueta inmutable. De forma predeterminada usa una marca de tiempo UTC.
#>
[CmdletBinding()]
param(
    [string]$ImageTag = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'),
    [string]$DefaultTicker = 'GOOGL',
    [switch]$SkipImagePush,
    [string]$InfraDirectory = (Join-Path $PSScriptRoot '..\infra')
)

$ErrorActionPreference = 'Stop'

foreach ($tool in @('aws', 'docker', 'terraform')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "No se encontró '$tool' en PATH. Consulte docs/GUIA_DESPLIEGUE.md."
    }
}
if ($ImageTag -notmatch '^[A-Za-z0-9_.-]{1,128}$') {
    throw 'ImageTag contiene caracteres no admitidos por Docker/ECR.'
}

$resolvedInfraDirectory = (Resolve-Path -LiteralPath $InfraDirectory).Path
$terraformChdir = "-chdir=$resolvedInfraDirectory"

$terraformOutputsJson = terraform $terraformChdir output -json
if ($LASTEXITCODE -ne 0) { throw 'No fue posible leer las salidas de Terraform.' }
$terraformOutputs = $terraformOutputsJson | ConvertFrom-Json
if (
    -not $terraformOutputs.ecr_repository_url.value -or
    -not $terraformOutputs.instance_id.value -or
    -not $terraformOutputs.aws_region.value
) {
    throw 'Terraform no registra infraestructura activa. Ejecute terraform plan y apply antes de desplegar.'
}
$repository = $terraformOutputs.ecr_repository_url.value
$instanceId = $terraformOutputs.instance_id.value
$region = $terraformOutputs.aws_region.value

$registry = $repository.Split('/')[0]
$imageUri = "${repository}:${ImageTag}"

if (-not $SkipImagePush) {
    Write-Host "Construyendo $imageUri"
    # EC2 t3 usa amd64. Desactivar provenance evita que Docker Desktop publique un
    # índice OCI auxiliar que algunos repositorios ECR restringidos rechazan.
    docker build --pull --platform linux/amd64 --provenance=false --tag $imageUri (Join-Path $PSScriptRoot '..')
    if ($LASTEXITCODE -ne 0) { throw 'Falló la construcción de la imagen.' }

    Write-Host 'Autenticando Docker en Amazon ECR'
    $previousDockerConfig = $env:DOCKER_CONFIG
    $temporaryDockerConfig = Join-Path ([System.IO.Path]::GetTempPath()) "stock-market-docker-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $temporaryDockerConfig | Out-Null
    try {
    # Un almacén efímero evita depender del credential helper de Docker Desktop,
    # que puede fallar al guardar tokens ECR en algunas instalaciones de Windows.
    $env:DOCKER_CONFIG = $temporaryDockerConfig
    $ecrPassword = aws ecr get-login-password --region $region
    if ($LASTEXITCODE -ne 0 -or -not $ecrPassword) {
        throw 'AWS CLI no pudo obtener el token de autenticación de ECR.'
    }

    # Escribe el formato estándar de autenticación Docker directamente. El token
    # solo vive en la carpeta temporal y se elimina en el bloque finally.
    $credential = [Convert]::ToBase64String(
        [Text.Encoding]::UTF8.GetBytes("AWS:$ecrPassword")
    )
    $dockerConfig = @{
        auths = @{
            $registry = @{ auth = $credential }
        }
    } | ConvertTo-Json -Depth 4
    $dockerConfigPath = Join-Path $temporaryDockerConfig 'config.json'
    [IO.File]::WriteAllText(
        $dockerConfigPath,
        $dockerConfig,
        [Text.UTF8Encoding]::new($false)
    )
    Write-Host 'Token temporal de ECR preparado'

        docker push $imageUri
        if ($LASTEXITCODE -ne 0) { throw 'Falló la publicación de la imagen.' }
    } finally {
        if ($null -eq $previousDockerConfig) {
            Remove-Item Env:DOCKER_CONFIG -ErrorAction SilentlyContinue
        } else {
            $env:DOCKER_CONFIG = $previousDockerConfig
        }
        Remove-Item -LiteralPath $temporaryDockerConfig -Recurse -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host "Se omite la publicación; se desplegará la imagen existente $imageUri"
}

Write-Host 'Esperando a que EC2 aparezca en AWS Systems Manager'
$online = $false
for ($attempt = 1; $attempt -le 30; $attempt++) {
    $status = aws ssm describe-instance-information `
        --region $region `
        --filters "Key=InstanceIds,Values=$instanceId" `
        --query 'InstanceInformationList[0].PingStatus' `
        --output text
    if ($status -eq 'Online') { $online = $true; break }
    Start-Sleep -Seconds 10
}
if (-not $online) {
    throw 'La instancia no está disponible en SSM. Revise cloud-init-output.log.'
}

# El documento JSON evita problemas de escape entre PowerShell, AWS CLI y Bash.
$commands = @(
    'set -eu',
    "aws ecr get-login-password --region '$region' | docker login --username AWS --password-stdin '$registry'",
    "docker pull '$imageUri'",
    'docker rm --force stock-market 2>/dev/null || true',
    "docker run --detach --name stock-market --restart unless-stopped --publish 80:8000 --env DEFAULT_TICKER='$DefaultTicker' '$imageUri'",
    "for attempt in `$(seq 1 30); do if curl --fail --silent http://127.0.0.1/health; then exit 0; fi; sleep 2; done; docker logs stock-market; exit 1"
)
$request = @{
    DocumentName = 'AWS-RunShellScript'
    InstanceIds  = @($instanceId)
    Comment      = "Deploy $imageUri"
    Parameters   = @{ commands = $commands }
} | ConvertTo-Json -Depth 6

$requestFile = Join-Path ([System.IO.Path]::GetTempPath()) "stock-market-ssm-$([guid]::NewGuid()).json"
try {
    [System.IO.File]::WriteAllText($requestFile, $request, [System.Text.UTF8Encoding]::new($false))
    $commandId = aws ssm send-command `
        --region $region `
        --cli-input-json "file://$requestFile" `
        --query 'Command.CommandId' `
        --output text
    if ($LASTEXITCODE -ne 0) { throw 'No fue posible enviar el comando de despliegue.' }

    aws ssm wait command-executed --region $region --command-id $commandId --instance-id $instanceId
    $result = aws ssm get-command-invocation `
        --region $region `
        --command-id $commandId `
        --instance-id $instanceId `
        --output json | ConvertFrom-Json
    Write-Host $result.StandardOutputContent
    if ($result.Status -ne 'Success') {
        Write-Error $result.StandardErrorContent
        throw "El despliegue terminó con estado $($result.Status)."
    }
} finally {
    Remove-Item -LiteralPath $requestFile -Force -ErrorAction SilentlyContinue
}

$applicationUrl = $terraformOutputs.application_url.value
Write-Host "Despliegue completado: $applicationUrl"
