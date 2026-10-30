<# Ejecuta comprobaciones locales sin crear recursos en AWS. #>
[CmdletBinding()]
param([switch]$SkipDocker)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')

python -m pytest (Join-Path $root 'tests')
if ($LASTEXITCODE -ne 0) { throw 'Las pruebas de Python fallaron.' }

if (Get-Command terraform -ErrorAction SilentlyContinue) {
    terraform -chdir=(Join-Path $root 'infra') fmt -check
    if ($LASTEXITCODE -ne 0) { throw 'terraform fmt encontró diferencias.' }
    terraform -chdir=(Join-Path $root 'infra') init -backend=false
    terraform -chdir=(Join-Path $root 'infra') validate
    if ($LASTEXITCODE -ne 0) { throw 'terraform validate falló.' }
} else {
    Write-Warning 'Terraform no está instalado; se omite su validación.'
}

if (-not $SkipDocker) {
    docker build --tag stock-market:validation $root
    if ($LASTEXITCODE -ne 0) { throw 'La construcción Docker falló.' }
}

Write-Host 'Validaciones completadas.'
