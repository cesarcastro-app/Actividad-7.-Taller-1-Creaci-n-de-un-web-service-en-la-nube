<#
.SYNOPSIS
Detiene la instancia EC2 del taller y confirma que alcanzó el estado stopped.

.DESCRIPTION
No elimina ECR, VPC, Elastic IP, volumen EBS ni el estado de Terraform. Puede
ejecutarse varias veces: si EC2 ya está detenida, termina correctamente.
#>
[CmdletBinding()]
param(
    [string]$InfraDirectory = (Join-Path $PSScriptRoot '..\infra')
)

$ErrorActionPreference = 'Stop'

foreach ($tool in @('aws', 'terraform')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "No se encontró '$tool' en PATH."
    }
}

$resolvedInfraDirectory = (Resolve-Path -LiteralPath $InfraDirectory).Path
$terraformChdir = "-chdir=$resolvedInfraDirectory"
$instanceId = terraform $terraformChdir output -raw instance_id
$region = terraform $terraformChdir output -raw aws_region
if ($LASTEXITCODE -ne 0 -or -not $instanceId -or -not $region) {
    throw 'No fue posible obtener la instancia y la región desde Terraform.'
}

function Get-InstanceState {
    $state = aws ec2 describe-instances `
        --region $region `
        --instance-ids $instanceId `
        --query 'Reservations[0].Instances[0].State.Name' `
        --output text
    if ($LASTEXITCODE -ne 0) {
        throw "No fue posible consultar la instancia $instanceId."
    }
    return $state.Trim()
}

$initialState = Get-InstanceState
Write-Host "Instancia: $instanceId"
Write-Host "Región:    $region"
Write-Host "Estado inicial: $initialState"

if ($initialState -eq 'terminated' -or $initialState -eq 'shutting-down') {
    throw "La instancia está en estado '$initialState' y no puede detenerse."
}

if ($initialState -ne 'stopped') {
    Write-Host 'Solicitando la detención de EC2...'
    aws ec2 stop-instances `
        --region $region `
        --instance-ids $instanceId `
        --output json | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'AWS rechazó la solicitud de detención.'
    }

    Write-Host 'Esperando hasta que la instancia quede detenida...'
    aws ec2 wait instance-stopped `
        --region $region `
        --instance-ids $instanceId
    if ($LASTEXITCODE -ne 0) {
        throw 'Se agotó la espera antes de confirmar el estado stopped.'
    }
} else {
    Write-Host 'La instancia ya estaba detenida; no se enviaron cambios.'
}

$finalState = Get-InstanceState
if ($finalState -ne 'stopped') {
    throw "Verificación fallida: el estado final es '$finalState'."
}

Write-Host "Verificación completada: $instanceId está stopped."
Write-Warning 'EBS, Elastic IP y ECR permanecen creados y pueden generar cargos.'
