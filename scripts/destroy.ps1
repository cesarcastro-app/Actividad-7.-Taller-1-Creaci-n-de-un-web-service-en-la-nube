<# Destruye los recursos del taller para detener cargos de AWS. #>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param([string]$InfraDirectory = (Join-Path $PSScriptRoot '..\infra'))

$ErrorActionPreference = 'Stop'
if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    throw "Terraform no está instalado o no se encuentra en PATH."
}
$resolvedInfraDirectory = (Resolve-Path -LiteralPath $InfraDirectory).Path
$terraformChdir = "-chdir=$resolvedInfraDirectory"

if ($PSCmdlet.ShouldProcess('infraestructura AWS de stock-market', 'terraform destroy')) {
    terraform $terraformChdir destroy
    if ($LASTEXITCODE -ne 0) { throw 'Terraform no pudo destruir toda la infraestructura.' }
}
