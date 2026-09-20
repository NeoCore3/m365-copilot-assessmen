#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][string]$RequestPath)
$ErrorActionPreference='Stop'
$request=Get-Content -LiteralPath $RequestPath -Raw|ConvertFrom-Json
$workerResults=[Collections.Generic.List[object]]::new()
$workerRows=[Collections.Generic.List[object]]::new()
. (Join-Path $PSScriptRoot 'Api.ps1')
. (Join-Path $PSScriptRoot 'Collectors.ps1')
. (Join-Path $PSScriptRoot 'WorkerSupport.ps1')

try {
 try { Connect-Worker }
 catch {
  $reason=$_.Exception.Message
  # Connection errors can contain module internals; use a bounded, token-redacted message.
  $reason=$reason -replace 'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+','[redacted token]'
  if($reason.Length -gt 1200){$reason=$reason.Substring(0,1200)}
  foreach($d in $request.Definitions){$workerResults.Add([pscustomobject]@{Id=$d.Id;Workstream=$d.Workstream;Source=$d.Source;Status='BlockedByConnection';Explanation="Connection failed: $reason";Rows=@()})}
 }
 if(-not $workerResults.Count){foreach($d in $request.Definitions){Invoke-WorkerDataset $d {Read-WorkerDataset $d}}}
} finally {
 $script:apiToken=$null
 [pscustomobject]@{TenantId=$request.TenantId;Cloud=$request.Cloud;RunId=$request.RunId;Workload=$request.Workload;Results=$workerResults.ToArray()}|ConvertTo-Json -Depth 70|Set-Content -LiteralPath $request.ResultPath -Encoding utf8
}
