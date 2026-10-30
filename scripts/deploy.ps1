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

$repository = terraform -chdir=$InfraDirectory output -raw ecr_repository_url
$instanceId = terraform -chdir=$InfraDirectory output -raw instance_id
$region = terraform -chdir=$InfraDirectory output -raw aws_region
if ($LASTEXITCODE -ne 0) { throw 'No fue posible leer las salidas de Terraform.' }

$registry = $repository.Split('/')[0]
$imageUri = "${repository}:${ImageTag}"

Write-Host "Construyendo $imageUri"
docker build --pull --tag $imageUri (Join-Path $PSScriptRoot '..')
if ($LASTEXITCODE -ne 0) { throw 'Falló la construcción de la imagen.' }

Write-Host 'Autenticando Docker en Amazon ECR'
aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $registry
if ($LASTEXITCODE -ne 0) { throw 'Falló la autenticación en ECR.' }

docker push $imageUri
if ($LASTEXITCODE -ne 0) { throw 'Falló la publicación de la imagen.' }

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
    'set -euo pipefail',
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

$applicationUrl = terraform -chdir=$InfraDirectory output -raw application_url
Write-Host "Despliegue completado: $applicationUrl"
