<# Destruye los recursos del taller para detener cargos de AWS. #>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param([string]$InfraDirectory = (Join-Path $PSScriptRoot '..\infra'))

$ErrorActionPreference = 'Stop'
if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    throw "Terraform no está instalado o no se encuentra en PATH."
}

if ($PSCmdlet.ShouldProcess('infraestructura AWS de stock-market', 'terraform destroy')) {
    terraform -chdir=$InfraDirectory destroy
    if ($LASTEXITCODE -ne 0) { throw 'Terraform no pudo destruir toda la infraestructura.' }
}
