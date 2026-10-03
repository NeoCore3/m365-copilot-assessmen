#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][string]$RunDirectory,[Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$source=[IO.Path]::GetFullPath($RunDirectory);$target=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $target){throw 'OutputDirectory must be a new folder. The original run is preserved.'}
if($target.StartsWith($source.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'OutputDirectory must be outside RunDirectory.'}
$m=Get-Content -LiteralPath (Join-Path $source 'manifest.json') -Raw|ConvertFrom-Json -Depth 100
foreach($r in $m.Results){if($r.Id -notmatch '^[A-Za-z0-9_-]+$' -or $r.Workstream -notmatch '^[A-Za-z0-9_-]+$'){throw 'Unsafe manifest identifier.'}}
New-Item -ItemType Directory -Path $target|Out-Null
Get-ChildItem -LiteralPath $source -Force|Copy-Item -Destination $target -Recurse
. (Join-Path $PSScriptRoot 'src/Report.ps1')
Export-AssessmentReview $m $target
Write-AssessmentReport $m $target
Write-Host "Rebuilt report: $(Join-Path $target 'Assessment.html'). No tenant connection or new collection was performed."
