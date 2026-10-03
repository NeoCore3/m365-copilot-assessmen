#requires -Version 7.4
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$temp=Join-Path ([IO.Path]::GetTempPath()) ('auth-console-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path (Join-Path $temp 'src') -Force|Out-Null
Copy-Item (Join-Path $root 'src/Launch.ps1') (Join-Path $temp 'Launch.ps1')
Copy-Item (Join-Path $root 'src/GraphSignIn.ps1') (Join-Path $temp 'src/GraphSignIn.ps1')
@'
param($ParametersPath)
$ErrorActionPreference='Stop'
$p=Get-Content $ParametersPath -Raw|ConvertFrom-Json
. (Join-Path $PSScriptRoot 'GraphSignIn.ps1')
function Connect-MgGraph {
 param([switch]$UseDeviceCode)
 Write-Output 'SYNTHETIC-CODE-VISIBLE-BEFORE-AUTH-COMPLETES'
 while(-not (Test-Path -LiteralPath $p.GatePath)){Start-Sleep -Milliseconds 50}
}
Connect-AssessmentGraphSession @{UseDeviceCode=$true}
exit 0
'@|Set-Content (Join-Path $temp 'src/Bootstrap.ps1')
@'
param($Root)
$ErrorActionPreference='Stop'
. (Join-Path $Root 'Launch.ps1')
Invoke-FreshAssessment @{GatePath=(Join-Path $Root 'gate')} $Root Commercial Interactive
'@|Set-Content (Join-Path $temp 'Entry.ps1')
$info=[Diagnostics.ProcessStartInfo]::new()
$info.FileName=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
$info.UseShellExecute=$false;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
foreach($arg in @('-NoProfile','-File',(Join-Path $temp 'Entry.ps1'),'-Root',$temp)){[void]$info.ArgumentList.Add($arg)}
$process=$null
try{
 $process=[Diagnostics.Process]::Start($info)
 $stderr=$process.StandardError.ReadToEndAsync()
 $deadline=[datetime]::UtcNow.AddSeconds(20);$visible=$false
 while([datetime]::UtcNow -lt $deadline){
  $line=$process.StandardOutput.ReadLineAsync()
  if(-not $line.Wait(10000)){break}
  if($null -eq $line.Result){break}
  if($line.Result -eq 'SYNTHETIC-CODE-VISIBLE-BEFORE-AUTH-COMPLETES'){$visible=$true;break}
 }
 if(-not $visible -or $process.HasExited){throw 'Authentication instructions did not reach the outer console while the nested process was waiting.'}
 'release'|Set-Content (Join-Path $temp 'gate')
 if(-not $process.WaitForExit(10000) -or $process.ExitCode -ne 0){throw 'Launcher did not finish after simulated authentication completed.'}
 Write-Host 'PASS: authentication output streamed through the real nested launcher before sign-in completed.'
}finally{
 if($process){if(-not $process.HasExited){$process.Kill($true)};$process.Dispose()}
 Remove-Item -LiteralPath $temp -Recurse -Force
}
