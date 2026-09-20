function Connect-Worker {
 switch($request.Workload){
  'Fabric' {Connect-AssessmentApi 'https://api.fabric.microsoft.com' @('https://api.fabric.microsoft.com/Tenant.Read.All','https://api.fabric.microsoft.com/Capacity.Read.All')}
  'Endpoint' {Connect-AssessmentApi 'https://api.securitycenter.microsoft.com' @('https://api.securitycenter.microsoft.com/SecurityRecommendation.Read')}
  'Agents' {if(-not $request.DataverseUrls.Count){throw 'IncludeAgents requires DataverseUrls for the approved environments.'}}
  {$_ -in @('GraphExtra','ItemPermissions')} {
   Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
   $p=@{TenantId=$request.TenantId;ContextScope='Process';NoWelcome=$true;ErrorAction='Stop'}
   if($request.Authentication -eq 'Certificate'){$p.ClientId=$request.ClientId;$p.CertificateThumbprint=$request.CertificateThumbprint}
   else {$p.Scopes=@($request.Definitions.Permission|Select-Object -Unique);if($request.ClientId){$p.ClientId=$request.ClientId}}
   Connect-MgGraph @p|Out-Null
   if((Get-MgContext).TenantId -ne $request.TenantId -or (Get-MgContext).Environment -ne 'Global'){throw 'Graph tenant/cloud mismatch.'}
  }
  {$_ -in @('Audit','Activity')} {
   Import-Module ExchangeOnlineManagement -ErrorAction Stop
   $command=if($_ -eq 'Audit'){'Connect-ExchangeOnline'}else{'Connect-IPPSSession'}
   $p=@{ErrorAction='Stop'}
   if($request.AdminUPN){$p.UserPrincipalName=$request.AdminUPN}
   if($request.Authentication -eq 'Certificate'){$p.Remove('UserPrincipalName');$p.AppId=$request.ClientId;$p.CertificateThumbprint=$request.CertificateThumbprint;$p.Organization=$request.Organization}
   if($request.DisableWAM){if(-not (Get-Command $command).Parameters.ContainsKey('DisableWAM')){throw "$command does not support DisableWAM; update ExchangeOnlineManagement."};$p.DisableWAM=$true}
   & $command @p|Out-Null
  }
  'SPOExtra' {
   Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell -ErrorAction Stop
   . (Join-Path $PSScriptRoot 'WorkloadPrerequisites.ps1')
   $u=[uri]$request.SharePointAdminUrl
   if($u.Scheme -ne 'https' -or $u.Host -notmatch '^[a-zA-Z0-9-]+-admin\.sharepoint\.com$' -or $u.Port -ne 443 -or $u.UserInfo){throw 'Provide a Commercial SharePointAdminUrl.'}
   $p=Get-AssessmentSpoParameters -Command (Get-Command Connect-SPOService) -Url $request.SharePointAdminUrl -Cloud Commercial -Authority 'https://login.microsoftonline.com' -Authentication $request.Authentication -ClientId $request.ClientId -TenantId $request.TenantId -CertificateThumbprint $request.CertificateThumbprint
   Connect-SPOService @p|Out-Null
  }
  'Teams' {
   Import-Module MicrosoftTeams -ErrorAction Stop
   $p=@{TenantId=$request.TenantId;ErrorAction='Stop'}
   if($request.Authentication -eq 'Certificate'){$p.ApplicationId=$request.ClientId;$p.CertificateThumbprint=$request.CertificateThumbprint}
   if($request.DisableWAM -and $request.Authentication -eq 'Interactive'){
    if(-not (Get-Command Connect-MicrosoftTeams).Parameters.ContainsKey('DisableWAM')){throw 'Update MicrosoftTeams to use DisableWAM.'};$p.DisableWAM=$true
   }
   $ctx=Connect-MicrosoftTeams @p
   if($ctx.TenantId -and $ctx.TenantId -ne $request.TenantId){throw 'Teams tenant mismatch.'}
  }
  'PowerPlatform' {
   Import-Module Microsoft.PowerApps.Administration.PowerShell -UseWindowsPowerShell -ErrorAction Stop
   Add-PowerAppsAccount -Endpoint prod -TenantID $request.TenantId -ErrorAction Stop|Out-Null
  }
  default {throw 'Unknown worker workload.'}
 }
}
function Read-GraphPages([string]$Path) {
 $next='https://graph.microsoft.com'+$Path;$seen=[Collections.Generic.HashSet[string]]::new();$page=0
 while($next){
  if(++$page -gt $request.MaxPages){throw 'Graph page limit reached.'}
  Assert-ApiUri $next 'https://graph.microsoft.com'
  if(-not $seen.Add($next)){throw 'Repeated Graph continuation.'}
  $r=Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject -ErrorAction Stop
  if($null -eq $r.PSObject.Properties['value']){throw 'Graph collection missing value.'}
  foreach($row in $r.value){Add-WorkerRow $row};$next=$r.'@odata.nextLink'
 }
}
function Read-Activity([string[]]$Activities) {
 $end=[datetime]::Parse($request.EndUtc).ToUniversalTime();$days=[math]::Min(30,[int]$request.Period.Substring(1));$start=$end.AddDays(-$days)
 $earliest=[datetime]::UtcNow.AddDays(-30).AddMinutes(1)
 if($start -lt $earliest){$start=$earliest}
 $script:datasetScope.StartUtc=$start.ToString('o');$script:datasetScope.EndUtc=$end.ToString('o');$script:datasetScope.Activities=$Activities
 $pages=0
 while($start -lt $end){
  $stop=if($start.AddDays(1) -lt $end){$start.AddDays(1)}else{$end};$cookie=$null;$seen=[Collections.Generic.HashSet[string]]::new()
  do {
   if(++$pages -gt $request.MaxPages){throw 'Activity Explorer page limit reached.'}
   $p=@{StartTime=$start;EndTime=$stop;OutputFormat='Json';PageSize=5000;Filter1=@('Activity')+$Activities;ErrorAction='Stop'}
   if($cookie){$p.PageCookie=$cookie}
   $r=Export-ActivityExplorerData @p
   if($null -eq $r.LastPage -or $null -eq $r.ResultData){throw 'Activity Explorer returned an unexpected response.'}
   foreach($row in @($r.ResultData|ConvertFrom-Json)){
    # Metadata only. Prompt/response text, file contents and arbitrary nested properties are excluded.
    Add-WorkerRow ($row|Select-Object Identity,Id,CreationTime,Activity,Operation,Workload,User,UserId,Application,CopilotAppHost,CopilotType,PolicyName,PolicyId,PolicyRuleName,PolicyRuleId,EnforcementMode,PolicyMode,SensitivityLabel,IsProtected)
   }
   $last=[string]$r.LastPage -eq 'True';$cookie=$r.Watermark
   if(-not $last -and (-not $cookie -or -not $seen.Add($cookie))){throw 'Missing or repeated Activity Explorer continuation.'}
  }while(-not $last)
  $start=$stop
 }
 if([int]$request.Period.Substring(1) -gt 30){throw 'Activity Explorer is limited to the last 30 days; the requested reporting period is longer.'}
}
function Read-Audit {
 $end=[datetime]::Parse($request.EndUtc).ToUniversalTime();$start=$end.AddDays(-[int]$request.Period.Substring(1))
 $script:datasetScope.StartUtc=$start.ToString('o');$script:datasetScope.EndUtc=$end.ToString('o');$script:datasetScope.Operations=@('CopilotInteraction')
 $ranges=[Collections.Generic.Queue[object]]::new();while($start -lt $end){$stop=if($start.AddDays(1) -lt $end){$start.AddDays(1)}else{$end};$ranges.Enqueue(@($start,$stop));$start=$stop}
 $seen=[Collections.Generic.HashSet[string]]::new();$pages=0
 while($ranges.Count){
  $range=$ranges.Dequeue();$session=[guid]::NewGuid().ToString();$count=0;$pageSeen=[Collections.Generic.HashSet[string]]::new()
  do {
   if(++$pages -gt $request.MaxPages){throw 'Audit page limit reached; narrow the period or increase MaxPages.'}
   $rows=@(Search-UnifiedAuditLog -StartDate $range[0] -EndDate $range[1] -Operations CopilotInteraction -SessionId $session -SessionCommand ReturnLargeSet -ResultSize 5000 -ErrorAction Stop)
   if($rows.Count){$fingerprint=($rows|ForEach-Object Identity)-join '|';if(-not $pageSeen.Add($fingerprint)){throw 'Audit search repeated a page.'}}
   $count+=$rows.Count
   foreach($row in $rows){
    $payload=$row.AuditData|ConvertFrom-Json
    $id=if($payload.Id){[string]$payload.Id}else{[string]$row.Identity}
    if(-not $id){throw 'Audit event missing its stable ID.'}
    if($seen.Add($id)){Add-WorkerRow ([pscustomobject]@{Id=$id;CreationTime=$payload.CreationTime;Operation=$payload.Operation;Workload=$payload.Workload;UserId=$payload.UserId;RecordType=$payload.RecordType;AppHost=$payload.CopilotEventData.AppHost;LicenseClassification='Unknown at event time'})}
   }
  }while($rows.Count -gt 0 -and $count -lt 50000)
  if($count -ge 50000){
   if(($range[1]-$range[0]).TotalSeconds -le 60){throw 'Audit service cap reached within a one-minute slice.'}
   $mid=$range[0].AddTicks([long](($range[1]-$range[0]).Ticks/2));$ranges.Enqueue(@($range[0],$mid));$ranges.Enqueue(@($mid,$range[1]))
  }
 }
}
function Read-Dag($Definition) {
 $reports=@(Get-SPODataAccessGovernanceInsight -ReportEntity $Definition.Entity -Workload $Definition.SpoWorkload -ErrorAction Stop)
 if(-not $reports.Count){throw 'No existing DAG report returned. Generate the required report in SharePoint admin center, then rerun.'}
 $incomplete=$false
 foreach($report in $reports){
  $status=[string]$report.Status;$id=[string]$report.ReportId;$files=@();$export='NotReady'
  if($status -in @('Completed','Available','Success')){
   try {
    $id=([guid]::Parse($id)).ToString();$folder=Join-Path $request.DownloadPath "$($Definition.Id)/$id";New-Item -ItemType Directory -Path $folder -Force|Out-Null
    Export-SPODataAccessGovernanceInsight -ReportID $id -DownloadPath $folder -ErrorAction Stop|Out-Null
    $files=@(Get-ChildItem -LiteralPath $folder -File -Recurse|ForEach-Object {[pscustomobject]@{Path=$_.FullName.Substring($request.DownloadPath.Length+1);SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash;Bytes=$_.Length}})
    if(-not $files.Count){throw 'Export created no files.'};$export='Downloaded'
   }catch{$export='ExportFailed';$incomplete=$true}
  }else{$incomplete=$true}
  Add-WorkerRow ([pscustomobject]@{ReportId=$id;ReportEntity=$Definition.Entity;Workload=$Definition.SpoWorkload;ServiceStatus=$status;ExportStatus=$export;Files=$files;ReportMetadata=$report})
 }
 if($incomplete){throw 'Some DAG reports were pending, unavailable, or failed to download; inspect each ExportStatus. Only existing reports are requested.'}
}
function Read-Items {
 if(-not $request.DriveIds.Count){throw 'Provide approved DriveIds for the bounded item-permissions scan.'}
 $scanned=0;$pages=0
 foreach($drive in $request.DriveIds){
  $drivePart=[uri]::EscapeDataString($drive);$next="https://graph.microsoft.com/v1.0/drives/$drivePart/root/delta?`$select=id,name,file,folder,deleted,parentReference";$seen=[Collections.Generic.HashSet[string]]::new()
  while($next){
   if(++$pages -gt $request.MaxPages){throw 'Item enumeration page limit reached.'};Assert-ApiUri $next 'https://graph.microsoft.com'
   if(-not $seen.Add($next)){throw 'Repeated item continuation.'}
   $r=Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject -ErrorAction Stop
   if($null -eq $r.PSObject.Properties['value']){throw 'Item collection missing value.'}
   foreach($item in $r.value){
    if($item.deleted){continue};if(++$scanned -gt $request.MaxItems){throw 'MaxItems reached; permissions scan is incomplete.'}
    $itemPart=[uri]::EscapeDataString($item.id);$permissionUrl="https://graph.microsoft.com/v1.0/drives/$drivePart/items/$itemPart/permissions";$permPages=0;$permSeen=[Collections.Generic.HashSet[string]]::new();$permissions=[Collections.Generic.List[object]]::new()
    try {
     while($permissionUrl){
      if(++$permPages -gt $request.MaxPages -or -not $permSeen.Add($permissionUrl)){throw 'Permission pagination limit or loop.'};Assert-ApiUri $permissionUrl 'https://graph.microsoft.com'
      $p=Invoke-MgGraphRequest -Method GET -Uri $permissionUrl -OutputType PSObject -ErrorAction Stop
      if($null -eq $p.PSObject.Properties['value']){throw 'Permissions collection missing value.'}
      foreach($permission in $p.value){$permissions.Add($permission)};$permissionUrl=$p.'@odata.nextLink'
     }
     Add-WorkerRow ([pscustomobject]@{DriveId=$drive;ItemId=$item.id;Name=$item.name;Status='Collected';Permissions=$permissions.ToArray()})
    }catch{Add-WorkerRow ([pscustomobject]@{DriveId=$drive;ItemId=$item.id;Name=$item.name;Status='Failed';Permissions=@()});throw 'An item permissions query failed; collected items retained.'}
   }
   $next=$r.'@odata.nextLink'
  }
 }
}
function Read-WorkerDataset($d) {
 switch($d.Mode){
  'Api' {Read-ApiPages $d.Path $d.Field $d.SkipPageSize}
  'Graph' {Read-GraphPages $d.Path}
  'CopilotV2' {
   $period=if($request.Period -eq 'D30'){'D28'}else{$request.Period};$script:datasetScope.EffectivePeriod=$period;$tmp=Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString()+'.csv')
   try {
    Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/copilot/reports/getMicrosoft365CopilotUsageUserDetail(period='$period',version='v2')" -OutputFilePath $tmp -ErrorAction Stop|Out-Null
    if(-not (Test-Path $tmp) -or (Get-Item $tmp).Length -eq 0){throw 'Copilot usage API returned no report body.'}
    foreach($row in @(Import-Csv -LiteralPath $tmp)){Add-WorkerRow $row}
   }finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
  }
  'Command' {foreach($row in @(& $d.Command -ErrorAction Stop)){
    if($row.Error -or ($row.Code -and $row.Message)){throw 'Power Platform returned a service error envelope.'};Add-WorkerRow $row
   }}
  'Flows' {foreach($env in @(Get-AdminPowerAppEnvironment -ErrorAction Stop)){foreach($row in @(Get-AdminFlow -EnvironmentName $env.EnvironmentName -ErrorAction Stop)){if($row.Error){throw 'Flow service error.'};Add-WorkerRow $row}}}
  'Activity' {Read-Activity $d.Activities}
  'Audit' {Read-Audit}
  'Dag' {Read-Dag $d}
  'SiteReviews' {foreach($row in @(Get-SPOSiteReview -ReportEntity All -ErrorAction Stop)){Add-WorkerRow $row}}
  'Items' {Read-Items}
  'Bots' {
   $u=[uri]$d.EnvironmentUrl
   if($u.Scheme -ne 'https' -or $u.Port -ne 443 -or $u.UserInfo -or $u.Host -notmatch '^[a-zA-Z0-9-]+\.crm\d*\.dynamics\.com$' -or $u.AbsolutePath -ne '/' -or $u.Query){throw 'DataverseUrls must be Commercial environment origins, e.g. https://contoso.crm.dynamics.com.'}
   $origin=$u.GetLeftPart([UriPartial]::Authority)
   Connect-AssessmentApi $origin @("$origin/user_impersonation")
   Read-ApiPages ($origin+'/api/data/v9.2/bots?$select=botid,name,_ownerid_value,statecode,statuscode,authenticationmode,authenticationtrigger,accesscontrolpolicy,authorizedsecuritygroupids,publishedon')
  }
  default {throw 'Unknown dataset mode.'}
 }
}
