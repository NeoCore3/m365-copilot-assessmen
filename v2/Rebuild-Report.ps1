#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReportDirectory,[Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$source=(Resolve-Path -LiteralPath $ReportDirectory).Path
$destination=[IO.Path]::GetFullPath($OutputDirectory)
$comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
if($destination.Equals($source,$comparison) -or $destination.StartsWith($source.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar,$comparison)){throw 'Choose a new output directory outside the source run.'}
if(Test-Path -LiteralPath $destination){throw 'OutputDirectory must not already exist; original evidence is preserved.'}
$manifest=Get-Content -LiteralPath (Join-Path $source 'manifest.json') -Raw|ConvertFrom-Json
New-Item -ItemType Directory -Path $destination|Out-Null
Get-ChildItem -LiteralPath $source -Force|Copy-Item -Destination $destination -Recurse -Force
. (Join-Path $PSScriptRoot 'src/Report.ps1')
Write-AssessmentReport -Manifest $manifest -Directory $destination
Write-Host "Rebuilt: $(Join-Path $destination 'Assessment.html')"
Write-Host 'No tenant queries were made. Original collection statuses, dates and evidence are unchanged; failures require recollection.'
