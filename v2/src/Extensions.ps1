$extensionCoverage=@(Get-Content (Join-Path $root 'config/coverage-v2.json') -Raw|ConvertFrom-Json)
function Invoke-AssessmentExtensions {
 $definitions=@(Get-Content (Join-Path $root 'config/extensions.json') -Raw|ConvertFrom-Json)
 if($DataverseUrls.Count){
  $index=0
  foreach($url in $DataverseUrls){
   $definitions+=[pscustomobject]@{Id=('DataverseBots'+(++$index));Workstream='Agents';Workload='Agents';Switch='IncludeAgents';Mode='Bots';EnvironmentUrl=$url;Source='Dataverse v9.2 bots';Explanation="Agent configuration in explicitly supplied environment $url; includes only rows visible to this identity. Publication and permissions need separate review.";Certificate=$true}
  }
  foreach($group in @($extensionCoverage|Where-Object Group -in @('AgentInventory','CopilotStudioSecurity'))){$group.Datasets=@($group.Datasets)+@($definitions|Where-Object Mode -eq 'Bots'|ForEach-Object Id)}
 }else{
  $definitions+=[pscustomobject]@{Id='DataverseBots';Workstream='Agents';Workload='Agents';Switch='IncludeAgents';Mode='Bots';EnvironmentUrl='';Source='Dataverse v9.2 bots';Explanation='Provide DataverseUrls for approved environments.';Certificate=$true}
 }
 $enabled=[Collections.Generic.List[object]]::new()
 foreach($d in $definitions){
  if($d.CoreSPO -and $Cloud -ne 'Commercial'){continue}
  $requested=($d.Switch -eq 'Always' -and -not $ExtensionsOnly) -or [bool](Get-Variable -Name $d.Switch -ValueOnly -ErrorAction SilentlyContinue)
  if(-not $requested){
   $hint=if($d.Switch -eq 'Always'){'Omitted by ExtensionsOnly; run without ExtensionsOnly to collect this dataset. '}else{"Enable -$($d.Switch). "}
   Add-Result $d.Workstream $d.Id 'NotRequested' $d.Source ($hint+$d.Explanation);continue
  }
  if($d.NotApplicableReason){Add-Result $d.Workstream $d.Id 'NotApplicable' $d.Source $d.NotApplicableReason;continue}
  if($Cloud -ne 'Commercial'){Add-Result $d.Workstream $d.Id 'CapabilityUnverified' $d.Source 'This new collector has not been verified for GCC/GCC High. No Commercial endpoint was called. Original cloud-aware collectors still run.';continue}
  if($Authentication -eq 'Certificate' -and -not $d.Certificate){Add-Result $d.Workstream $d.Id 'AuthenticationUnverified' $d.Source 'This collector currently supports interactive mode only; certificate command-level support has not been verified. It will not prompt during an unattended run.';continue}
  $enabled.Add($d)
 }
 foreach($group in @($enabled|Group-Object Workload)){
  Write-Host "V2: collecting $($group.Name) in an isolated PowerShell process."
  $workerDirectory=Join-Path $directory ('workers/'+$group.Name);New-Item -ItemType Directory -Path $workerDirectory -Force|Out-Null
  $requestPath=Join-Path $workerDirectory 'request.json';$resultPath=Join-Path $workerDirectory 'result.json'
  $requestData=@{TenantId="$TenantId";Cloud=$Cloud;RunId=$runId;Authentication=$Authentication;ClientId=$ClientId;ApiClientId=$ApiClientId;CertificateThumbprint=$CertificateThumbprint;Organization=$Organization;AdminUPN=$AdminUPN;SharePointAdminUrl=$SharePointAdminUrl;DisableWAM=[bool]$DisableWAM;Period=$Period;EndUtc=$manifest.CollectedAtUtc;DataverseUrls=@($DataverseUrls);DriveIds=@($DriveIds);MaxPages=$MaxPages;MaxRows=$MaxRows;MaxItems=$MaxItems;Workload=$group.Name;Definitions=@($group.Group);ResultPath=$resultPath;DownloadPath=(Join-Path $directory 'downloads')}
  $requestData|ConvertTo-Json -Depth 15|Set-Content -LiteralPath $requestPath -Encoding utf8
  try {
   & (Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})) -NoProfile -File (Join-Path $PSScriptRoot 'Worker.ps1') -RequestPath $requestPath
   if($LASTEXITCODE -ne 0 -or -not (Test-Path $resultPath)){throw 'Worker exited without valid results. Check module installation and script execution policy.'}
   $data=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json -Depth 100
   if($data.TenantId -ne "$TenantId" -or $data.Cloud -ne $Cloud -or $data.RunId -ne $runId -or $data.Workload -ne $group.Name){throw 'Worker provenance mismatch.'}
   $expected=@($group.Group.Id);$actual=@($data.Results.Id)
   if($actual.Count -ne $expected.Count -or @($actual|Select-Object -Unique).Count -ne $actual.Count -or @($actual|Where-Object {$_ -notin $expected}).Count){throw 'Worker dataset mismatch.'}
   foreach($r in $data.Results){
    Add-Result $r.Workstream $r.Id $r.Status $r.Source $r.Explanation @($r.Rows)
    if($r.Scope){$results[$results.Count-1]|Add-Member -NotePropertyName Scope -NotePropertyValue $r.Scope}
    if($r.Status -in @('Failed','Incomplete','BlockedByConnection','CommandUnavailable')){
     $diagnostics.Add([pscustomobject]@{Id=$r.Id;Source=$r.Source;Category=$r.Status;Message=$r.Explanation;CollectedAtUtc=[datetime]::UtcNow.ToString('o')})
    }
   }
  }catch{foreach($d in $group.Group){Add-Result $d.Workstream $d.Id 'Failed' $d.Source $_.Exception.Message}}
  finally{Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue}
 }
 . (Join-Path $PSScriptRoot 'EvidenceQuality.ps1')
 $quality=@(foreach($id in @('TeamsUsage','SharePointUsage','OneDriveUsage','M365ActiveUsers','CopilotLicensedUsage','CopilotLicensedUsageV2')){
  $path=Join-Path $directory ('raw/'+$id+'.json')
  if(Test-Path -LiteralPath $path){Get-ReportIdentityQuality $id @(Get-Content -LiteralPath $path -Raw|ConvertFrom-Json)}
 })
 Add-Result 'Reporting' 'ReportIdentityQuality' 'Derived' 'Returned usage-report fields' 'Observed missing/concealed identifier counts. This does not read or change the tenant privacy setting.' $quality
 # Derived evidence references contain no automated approval or license-reclamation verdict.
 $refs=foreach($c in $extensionCoverage){foreach($id in $c.Datasets){$r=$results|Where-Object Id -eq $id;if($r){[pscustomobject]@{Category=$c.Group;Dataset=$id;Status=$r.Status;EvidenceFile="csv/$id.csv";Remaining=$c.Remaining;Approval='Human review required'}}}}
 Add-Result 'Governance' 'ExpansionEvidenceIndex' 'Derived' 'Current run collection-status' 'Evidence references only. No expansion gate has been approved.' @($refs)
 $license=$results|Where-Object Id -eq 'Licenses'
 if($license.Status -eq 'Collected'){
  $rows=foreach($l in @(Get-Content (Join-Path $directory 'raw/Licenses.json') -Raw|ConvertFrom-Json)){
   [pscustomobject]@{Sku=$l.skuPartNumber;Enabled=$l.prepaidUnits.enabled;Consumed=$l.consumedUnits;Unallocated=([long]$l.prepaidUnits.enabled-[long]$l.consumedUnits);UsageEvidence='CopilotLicensedUsageV2';Decision='Reconcile SKU/user identity and report dates before recommending reclamation.'}
  }
  Add-Result 'Copilot' 'LicenseAllocationIndicators' 'Derived' 'Licenses dataset' 'Subscription allocation indicators for all SKUs; these do not identify inactive users or reproduce portal optimization recommendations.' @($rows)
 }elseif($ExtensionsOnly){Add-Result 'Copilot' 'LicenseAllocationIndicators' 'NotRequested' 'Licenses dataset' 'Core licensing collection was excluded by ExtensionsOnly.'}else{Add-Result 'Copilot' 'LicenseAllocationIndicators' 'BlockedByConnection' 'Licenses dataset' 'Source license collection did not succeed.'}
 Export-SafeCsv -Rows @($refs) -Path (Join-Path $directory 'coverage-v2.csv')
}
