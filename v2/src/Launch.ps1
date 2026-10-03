function Invoke-FreshAssessment {
 param([Collections.IDictionary]$Parameters,[string]$Root,[string]$Cloud,[string]$Authentication)
 $temp=Join-Path ([IO.Path]::GetTempPath()) ('m365-assessment-'+[guid]::NewGuid().ToString('N')+'.json')
 $p=@{};foreach($key in $Parameters.Keys){$value=$Parameters[$key];$p[$key]=if($value -is [Management.Automation.SwitchParameter]){[bool]$value}else{$value}}
 $p.Cloud=$Cloud;$p.Authentication=$Authentication
 try{
  ConvertTo-Json -InputObject $p -Depth 10|Set-Content -LiteralPath $temp -Encoding utf8
  Write-Host 'Starting assessment in a fresh PowerShell process to avoid loaded-module conflicts.'
  & (Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})) -NoProfile -File (Join-Path $Root 'src/Bootstrap.ps1') -ParametersPath $temp
  if($LASTEXITCODE -ne 0){throw "Assessment process exited with code $LASTEXITCODE. Review the output and diagnostics."}
 }finally{Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue}
}
