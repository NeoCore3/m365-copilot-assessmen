#requires -Version 7.4
param([Parameter(Mandatory)][string]$ParametersPath)
$ErrorActionPreference='Stop'
$p=Get-Content -LiteralPath $ParametersPath -Raw|ConvertFrom-Json -AsHashtable
& (Join-Path $PSScriptRoot 'Invoke-Assessment.ps1') @p
