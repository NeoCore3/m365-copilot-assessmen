$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/Runtime.ps1')
. (Join-Path $root 'src/WorkerSupport.ps1')
. (Join-Path $root 'src/Collectors.ps1')
. (Join-Path $root 'src/DagReview.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('assessment-preview5-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $temp|Out-Null
try{
 $progress=Join-Path $temp 'progress.json'
 Write-AssessmentProgressFile $progress @{Detail='Ready'}
 if((Read-AssessmentProgressFile $progress).Detail -ne 'Ready'){throw 'Progress round trip failed.'}
 $workerRows=[Collections.Generic.List[object]]::new();$workerResults=[Collections.Generic.List[object]]::new()
 $request=[pscustomobject]@{ProgressPath=$progress;Definitions=@(1);Period='D7';EndUtc='2026-01-08T00:00:00Z';MaxRows=100;MaxPages=50;MaxItems=100;DownloadPath=$temp}
 $seenSessions=[Collections.Generic.HashSet[string]]::new()
 function Search-UnifiedAuditLog {
  param($StartDate,$EndDate,$Operations,$SessionId,$SessionCommand,$ResultSize,$ErrorAction)
  if($seenSessions.Add($SessionId)){
   [pscustomobject]@{Identity=$SessionId;AuditData=(@{Id=$SessionId;Operation='CopilotInteraction';CreationTime=$StartDate}|ConvertTo-Json)}
  }
 }
 $def=[pscustomobject]@{Id='CopilotAuditActivity';Workstream='Purview';Source='Synthetic';Explanation='Synthetic'}
 # FileShare.None reproduces the Windows destination lock from the customer run.
 $lock=[IO.File]::Open($progress,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
 try{Invoke-WorkerDataset $def {Read-Audit}}finally{$lock.Dispose()}
 if($workerResults[0].Status -ne 'Collected' -or $workerResults[0].Rows.Count -ne 7){throw 'Progress contention interrupted Audit.'}
 if(@(Get-ChildItem $temp -Filter '*.tmp').Count){throw 'Progress temporary files leaked.'}
 Write-AssessmentProgressFile $progress @{Detail='Recovered'}
 if((Read-AssessmentProgressFile $progress).Detail -ne 'Recovered'){throw 'Progress did not recover after lock release.'}
 Invoke-WorkerDataset $def {Add-WorkerRow @{Id='retained'};throw 'Synthetic service failure'}
 if($workerResults[1].Status -ne 'Incomplete' -or $workerResults[1].Explanation -notmatch 'Synthetic service failure'){throw 'Service failure was hidden.'}
 # Bad telemetry destination must also be nonfatal.
 Write-AssessmentProgressFile (Join-Path $temp 'missing/progress.json') @{Detail='Ignored'}
 $dag=[pscustomobject]@{Id='DAGTest';Workstream='SharePoint';Source='Synthetic';Explanation='Synthetic';Entity='SharingLinks_Anyone';SpoWorkload='SharePoint';ReportType='RecentActivity'}
 function Get-SPODataAccessGovernanceInsight {
  param($ReportEntity,$Workload,$ReportType,$ErrorAction)
  if($ReportType -ne 'RecentActivity' -or $Workload -ne 'SharePoint'){throw 'Wrong DAG scope'}
  [pscustomobject]@{ReportId='00000000-0000-0000-0000-000000000001';Status='InQueue';ReportType=$ReportType}
 }
 Invoke-WorkerDataset $dag {Read-Dag $dag}
 if($workerResults[2].Status -ne 'Incomplete' -or $workerResults[2].Rows[0].ExportStatus -ne 'NotReady' -or $workerResults[2].Scope.DagQuery.ReportType -ne 'RecentActivity'){throw 'Pending DAG misclassified.'}
 function Get-SPODataAccessGovernanceInsight {param($ReportEntity,$Workload,$ReportType,$ErrorAction)}
 Invoke-WorkerDataset $dag {Read-Dag $dag}
 if($workerResults[3].Status -ne 'NoExistingReport'){throw 'Missing DAG misclassified.'}
 $download=Join-Path $temp 'downloads/DAGTest';New-Item -ItemType Directory -Path $download -Force|Out-Null
 @([pscustomobject]@{Url='https://example.invalid/site';Name='<script>alert(1)</script>'},[pscustomobject]@{Url='https://example.invalid/site2';Name='Two'})|Export-Csv (Join-Path $download 'report.csv') -NoTypeInformation
 '"Url","Name"'|Set-Content (Join-Path $download 'empty.csv')
 $raw=Join-Path $temp 'raw.json'
 @(@{ReportId='synthetic';ServiceStatus='Completed';ExportStatus='Downloaded';ReportMetadata=@{};Files=@(@{Path='DAGTest/report.csv'},@{Path='DAGTest/empty.csv'},@{Path='../outside.csv'})})|ConvertTo-Json -Depth 8|Set-Content $raw
 $artifacts=@(Get-AssessmentDagArtifacts $temp $raw)
 if($artifacts.Count -ne 2 -or $artifacts[0].rowCount -ne 2 -or $artifacts[1].rowCount -ne 0 -or $artifacts[0].rows[0].Url -ne 'https://example.invalid/site'){throw 'DAG artifact preview/count/path validation failed.'}
 $catalog=Get-Content (Join-Path $root 'config/collectors.json') -Raw|ConvertFrom-Json
 if(@($catalog|Where-Object Id -eq 'CopilotLicensedUsage').Count){throw 'Obsolete duplicate v1 query remains.'}
 Write-Host 'Preview.5 passed: Audit under exclusive progress lock, telemetry recovery, real errors retained, DAG report filters/pending/missing, artifact rows/empty CSV/path checks, obsolete query removed.'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
