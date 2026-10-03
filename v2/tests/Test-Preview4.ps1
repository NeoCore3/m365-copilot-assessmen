#requires -Version 7.4
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/DagExport.ps1')
. (Join-Path $root 'src/Api.ps1')
. (Join-Path $root 'src/AgentCatalog.ps1')
. (Join-Path $root 'src/WorkerSupport.ps1')
. (Join-Path $root 'src/Report.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('preview4-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $temp|Out-Null
try{
 $script:target=Join-Path $temp 'nested-label/report.csv';$script:calls=0
 function Export-SPODataAccessGovernanceInsight {
  param($ReportID,$DownloadPath,$ErrorAction)
  $script:calls++
  if(-not (Test-Path ([IO.Path]::GetDirectoryName($script:target)))){throw "Could not find a part of the path '$script:target'."}
  'Name,Count'|Set-Content -LiteralPath $script:target
 }
 Export-AssessmentDagReport '00000000-0000-0000-0000-000000000001' $temp
 if($script:calls -ne 2 -or -not (Test-Path $script:target)){throw 'Contained DAG filename retry failed.'}
 $script:target=Join-Path $temp '../outside/report.csv';$script:calls=0;$blocked=$false
 try{Export-AssessmentDagReport '00000000-0000-0000-0000-000000000001' $temp}catch{$blocked=$true}
 if(-not $blocked -or $script:calls -ne 1){throw 'DAG retry accepted a traversal path.'}
 $script:target=Join-Path ([IO.Path]::GetTempPath()) ('outside-'+[guid]::NewGuid()+'/report.csv');$script:calls=0;$blocked=$false
 try{Export-AssessmentDagReport '00000000-0000-0000-0000-000000000001' $temp}catch{$blocked=$true}
 if(-not $blocked -or $script:calls -ne 1){throw 'DAG retry accepted an external path.'}
 $request=[pscustomobject]@{MaxRows=100;MaxPages=5;MaxItems=10;Period='D30'}
 $workerRows=[Collections.Generic.List[object]]::new();$workerResults=[Collections.Generic.List[object]]::new()
 $script:mode='partial';$script:uris=[Collections.Generic.List[string]]::new()
 function Invoke-MgGraphRequest {
  param($Method,$Uri,$OutputType,$ErrorAction)
  $script:uris.Add($Uri)
  if($Uri.EndsWith('/packages')){return [pscustomobject]@{value=@([pscustomobject]@{id='a';displayName='A'});'@odata.nextLink'='https://graph.microsoft.com/v1.0/copilot/admin/catalog/packages?skip=opaque'}}
  if($Uri.EndsWith('?skip=opaque')){return [pscustomobject]@{value=@([pscustomobject]@{id='b';displayName='B'})}}
  if($Uri.EndsWith('/a')){return [pscustomobject]@{id='a';allowedUsersAndGroups=@('Synthetic')}}
  if($script:mode -eq 'partial'){throw '403 Synthetic detail access error'}
  return [pscustomobject]@{id='b'}
 }
 $definition=[pscustomobject]@{Id='AgentCatalogDetails';Workstream='Agents';Source='Synthetic';Explanation='Synthetic'}
 Invoke-WorkerDataset $definition {Read-AgentCatalog}
 if($workerResults[0].Status -ne 'Incomplete' -or $workerResults[0].Rows.Count -ne 2 -or $workerResults[0].Rows[1].DetailStatus -ne 'Failed'){throw 'Detail failure lost inventory or reported complete.'}
 if($script:uris.Count -ne 4){throw 'Pagination/detail request count incorrect.'}
 $script:mode='success';Invoke-WorkerDataset $definition {Read-AgentCatalog}
 if($workerResults[1].Status -ne 'Collected'){throw 'Successful catalog did not collect.'}
 $request.MaxItems=1;Invoke-WorkerDataset $definition {Read-AgentCatalog}
 if($workerResults[2].Status -ne 'Incomplete' -or $workerResults[2].Rows.Count -ne 1){throw 'Item limit not preserved.'}
 $m=[pscustomobject]@{Results=@([pscustomobject]@{Id='DSPM';Status='PartialCoverage';Workstream='Purview'},[pscustomobject]@{Id='GraphConnection';Status='Failed';Workstream='Connection'},[pscustomobject]@{Id='UserAssignments';Status='BlockedByConnection';Workstream='Licensing';Source='/v1.0/users'})}
 $actions=@(Get-AssessmentActions $m)
 if($actions[0].EntryType -ne 'Assessment coverage' -or $actions[1].EntryType -ne 'Connection' -or $actions[2].EntryType -ne 'Dataset'){throw 'Coverage and collection entries conflated.'}
 if($actions[2].NextAction -notmatch 'GraphAuthMode'){throw 'Graph recovery action missing.'}
 foreach($wrapper in @(Get-ChildItem $root -Recurse -Filter 'Start-*.ps1')){
  $command=Get-Command $wrapper.FullName
  foreach($parameter in @('GraphAuthMode','RequireGraph','IncludeAgentCatalog')){if(-not $command.Parameters.ContainsKey($parameter)){throw "Missing $parameter in $wrapper"}}
 }
 function Import-Module {param($Name,$RequiredVersion,$ErrorAction)}
 $authProbe=@{DeviceSeen=$false;Visible=""}
 function Out-Host { process { $authProbe.Visible += [string]$_ } }
 function Connect-MgGraph {
  param($TenantId,$Environment,$ContextScope,$NoWelcome,$ErrorAction,$Scopes,$ClientId,[switch]$UseDeviceCode)
  $authProbe.DeviceSeen=[bool]$UseDeviceCode
  Write-Output 'SYNTHETIC DEVICE SIGN-IN INSTRUCTIONS'
  throw 'InteractiveBrowserCredential authentication failed: User canceled authentication.'
 }
 $stopped=$false
 try{
  & (Join-Path $root 'src/Invoke-Assessment.ps1') -TenantId '00000000-0000-0000-0000-000000000001' -CustomerName 'Synthetic' -Cloud Commercial -Authentication Interactive -GraphAuthMode DeviceCode -RequireGraph -IncludePurview -OutputRoot (Join-Path $temp 'stopped')
 }catch{if($_.Exception.Message -notmatch 'Required Graph sign-in failed'){throw};$stopped=$true}
 $manifestFile=Get-ChildItem (Join-Path $temp 'stopped') -Recurse -Filter manifest.json|Select-Object -First 1
 $m=Get-Content $manifestFile.FullName -Raw|ConvertFrom-Json
 if($authProbe.Visible -notmatch 'SYNTHETIC DEVICE SIGN-IN INSTRUCTIONS'){throw 'Device sign-in instructions were suppressed.'}
 if(-not $stopped -or -not $authProbe.DeviceSeen -or $m.RunCompleted -or $m.Results.Count -ne 1 -or $m.Results[0].Id -ne 'GraphConnection'){throw 'Graph device-code/early-stop semantics failed.'}
 if(-not (Test-Path (Join-Path $manifestFile.DirectoryName 'diagnostics.csv'))){throw 'Early stop lost diagnostics.'}
 Write-Host 'Preview.4 tests passed: DAG contained retry/path rejection, catalog pagination/details/limits, entry classification, six launcher parameters, Graph device-code and early-stop diagnostics.'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
