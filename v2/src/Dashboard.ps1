. (Join-Path $PSScriptRoot 'DagReview.ps1')
function Write-AssessmentReport {
 param($Manifest,[string]$Directory)
 if(-not (Test-Path (Join-Path $Directory 'readable'))){Export-AssessmentReview $Manifest $Directory}
 $actions=@(Get-AssessmentActions $Manifest)
 Export-SafeCsv $actions (Join-Path $Directory 'next-actions.csv')
 $items=@(foreach($r in $Manifest.Results){
  $action=$actions|Where-Object Id -eq $r.Id|Select-Object -First 1
  $artifacts=@()
  $rawPath=Join-Path $Directory "raw/$($r.Id).json"
  if($r.Id -like 'DAG*' -and (Test-Path -LiteralPath $rawPath)){
   $artifacts=@(Get-AssessmentDagArtifacts $Directory $rawPath)
  }
  if($r.Id -notmatch '^[A-Za-z0-9_-]+$'){throw 'Unsafe dataset identifier.'}
  $path=Join-Path $Directory "readable/$($r.Id).csv"
  $preview=@();$columns=@()
  if(Test-Path -LiteralPath $path){
   $preview=@(Import-Csv -LiteralPath $path|Select-Object -First 50)
   if($preview.Count){$columns=@($preview[0].PSObject.Properties.Name|Select-Object -First 20)}
  }
  [ordered]@{id=$r.Id;entryType=$action.EntryType;nextAction=$action.NextAction;artifacts=$artifacts;workstream=$r.Workstream;status=$r.Status;count=[long]$r.RowCount;source=$r.Source;explanation=$r.Explanation;at=$r.CollectedAtUtc;scope=$r.Scope;columns=$columns;rows=@(foreach($row in $preview){$v=[ordered]@{};foreach($c in $columns){$s=[string]$row.$c;$v[$c]=if($s.Length -gt 2000){$s.Substring(0,2000)+' [preview shortened; open CSV/JSON]'}else{$s}};$v});raw=(Test-Path (Join-Path $Directory "raw/$($r.Id).json"))}
 })
 $artifactIndex=@(foreach($item in $items){foreach($a in $item.artifacts){[pscustomobject]@{Dataset=$item.id;ReportId=$a.reportId;ServiceStatus=$a.serviceStatus;ExportStatus=$a.exportStatus;DataRows=$a.rowCount;Created=$a.created;ReportStart=$a.start;ReportEnd=$a.end;File=$a.relativePath;PreviewError=$a.previewError}}})
 Export-SafeCsv $artifactIndex (Join-Path $Directory 'dag-artifacts.csv')
 $metrics=@(foreach($spec in @(@('Directory users','UserAssignments','Directory records, including disabled accounts'),@('SharePoint sites','SharePointSites','Returned site inventory'),@('OneDrive sites','OneDriveSites','Returned personal-site inventory'),@('Sensitivity labels','SensitivityLabels','Configuration records; not enforcement tests'),@('DLP policies','DlpPolicies','Configuration records; review mode and scope'),@('Power Platform environments','PowerPlatformEnvironments','Returned environment inventory'),@('Copilot usage rows','CopilotLicensedUsageV2','Licensed-user report rows; not necessarily active users'),@('AI activity events','AIActivityMetadata','Returned metadata; see effective reporting window'))){
  $r=$Manifest.Results|Where-Object Id -eq $spec[1]|Select-Object -First 1
  [ordered]@{label=$spec[0];id=$spec[1];value=$(if($r -and $r.Status -in @('Collected','Incomplete')){[long]$r.RowCount}else{$null});status=$(if($r){$r.Status}else{'Not collected'});note=$spec[2]}
 })
 $sharing=@();$sites=$Manifest.Results|Where-Object Id -eq SharePointSites
 if($sites.Status -eq 'Collected' -and (Test-Path (Join-Path $Directory 'raw/SharePointSites.json'))){$sharing=@(Get-Content (Join-Path $Directory 'raw/SharePointSites.json') -Raw|ConvertFrom-Json|Group-Object SharingCapability|ForEach-Object {@{label=$(if($_.Name){$_.Name}else{'Not returned'});value=$_.Count}})}
 $data=[ordered]@{customer=$Manifest.CustomerName;tenant=$Manifest.TenantId;cloud=$Manifest.Cloud;auth=$Manifest.Authentication;period=$Manifest.Period;started=$Manifest.CollectedAtUtc;completed=$Manifest.CompletedAtUtc;version=$Manifest.ToolkitVersion;renderedWith='2.0.0-preview.5';metrics=$metrics;datasets=$items;sharing=$sharing}
 $json=ConvertTo-Json -InputObject $data -Depth 40 -Compress -EscapeHandling EscapeHtml
 $template=Get-Content (Join-Path $PSScriptRoot '../templates/dashboard.html') -Raw
 $template.Replace('__ASSESSMENT_DATA__',$json)|Set-Content -LiteralPath (Join-Path $Directory 'Assessment.html') -Encoding utf8
}
