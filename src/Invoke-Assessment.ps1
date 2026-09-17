#requires -Version 7.2
[CmdletBinding()]
param(
 [Parameter(Mandatory)][guid]$TenantId,
 [Parameter(Mandatory)][string]$CustomerName,
 [Parameter(Mandatory)][ValidateSet('Commercial','GCC','GCCHigh')][string]$Cloud,
 [Parameter(Mandatory)][ValidateSet('Interactive','Certificate')][string]$Authentication,
 [string]$ClientId, [string]$CertificateThumbprint, [string]$Organization, [string]$AdminUPN,
 [string]$SharePointAdminUrl,
 [ValidateSet('D7','D30','D90','D180')][string]$Period='D90',
 [string]$OutputRoot=(Join-Path $env:LOCALAPPDATA 'M365Assessment'),
 [string]$EvidencePath,
 [switch]$IncludePurview, [switch]$IncludeSharePoint, [switch]$IncludeDefender
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Report.ps1')
$root = Split-Path $PSScriptRoot -Parent
$profile = Get-Content (Join-Path $root "config/$Cloud.json") -Raw | ConvertFrom-Json
$catalog = @(Get-Content (Join-Path $root 'config/collectors.json') -Raw | ConvertFrom-Json)
if ($Authentication -eq 'Certificate' -and (-not $ClientId -or -not $CertificateThumbprint)) { throw 'Certificate mode requires ClientId and CertificateThumbprint.' }
if ($Authentication -eq 'Certificate' -and $IncludePurview -and -not $Organization) { throw 'Purview certificate mode requires the tenant initial Organization domain.' }
if ($IncludeSharePoint) {
 $uri = [uri]$SharePointAdminUrl
 if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or -not $uri.Host.EndsWith($profile.SharePointSuffix) -or $uri.Host -notmatch '-admin\.sharepoint\.') { throw 'Provide the correct HTTPS SharePoint admin URL for the selected cloud.' }
}
# Unique run folders prevent stale data being mistaken for a current collection.
$runId = [datetime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$directory = Join-Path $OutputRoot "$Cloud-$TenantId-$runId"
foreach ($d in @($directory,(Join-Path $directory 'raw'),(Join-Path $directory 'csv'))) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
$results = [System.Collections.Generic.List[object]]::new()
$manifest = [ordered]@{SchemaVersion='1.0';CustomerName=$CustomerName;TenantId="$TenantId";Cloud=$Cloud;Authentication=$Authentication;Period=$Period;CollectedAtUtc=[datetime]::UtcNow.ToString('o');Results=$results}
function Add-Result {
 param([string]$Workstream,[string]$Id,[string]$Status,[string]$Source,[string]$Explanation,[object[]]$Rows=@())
 $Rows = @($Rows | Where-Object { $null -ne $_ })
 if ($Status -in @('Collected','Imported')) {
  ConvertTo-Json -InputObject $Rows -Depth 50 | Set-Content -LiteralPath (Join-Path $directory "raw/$Id.json") -Encoding utf8
  Export-SafeCsv -Rows $Rows -Path (Join-Path $directory "csv/$Id.csv")
 } else {
  Export-SafeCsv -Rows @([pscustomobject]@{CollectionStatus=$Status;Explanation=$Explanation;Source=$Source}) -Path (Join-Path $directory "csv/$Id.csv")
 }
 $results.Add([pscustomobject]@{Workstream=$Workstream;Id=$Id;Status=$Status;RowCount=$Rows.Count;Source=$Source;CollectedAtUtc=[datetime]::UtcNow.ToString('o');Explanation=$Explanation})
}
. (Join-Path $PSScriptRoot 'Graph.ps1')
function Invoke-ReadCollector {
 param([string]$Workstream,[string]$Id,[string]$Source,[string]$Explanation,[scriptblock]$Read)
 try { $rows=@(& $Read); Add-Result $Workstream $Id 'Collected' $Source $Explanation $rows }
 catch { Add-Result $Workstream $Id 'Failed' $Source ($Explanation + ' Collection failed: ' + $_.Exception.GetType().Name + '. Verify module, role, consent, service availability and connectivity; no zero result inferred.') }
}
$graphConnected=$false; $exchangeConnected=$false; $spoConnected=$false
try {
 try {
  Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
  $connect=@{TenantId="$TenantId";Environment=$profile.GraphEnvironment;ContextScope='Process';NoWelcome=$true;ErrorAction='Stop'}
  if ($Authentication -eq 'Certificate') {
   $connect.ClientId=$ClientId; $connect.CertificateThumbprint=$CertificateThumbprint
  } else {
   $connect.Scopes=@($catalog | Where-Object { $_.Permission -and ($IncludeDefender -or $_.Workstream -ne 'Defender') -and ($Cloud -ne 'GCCHigh' -or -not $_.GlobalOnly) } | Select-Object -ExpandProperty Permission -Unique)
   if ($ClientId) { $connect.ClientId=$ClientId }
  }
  Connect-MgGraph @connect | Out-Null
  $ctx=Get-MgContext
  if ($ctx.TenantId -ne "$TenantId" -or $ctx.Environment -ne $profile.GraphEnvironment) { throw 'Graph tenant/cloud mismatch.' }
  $graphConnected=$true
 } catch {
  Add-Result 'Connection' 'GraphConnection' 'Failed' 'Connect-MgGraph' 'Graph authentication or context validation failed. Verify tenant, cloud, module, consent and credentials.'
 }
 foreach ($c in @($catalog | Where-Object Kind -ne 'Manual')) {
  if ($c.Workstream -eq 'Defender' -and -not $IncludeDefender) {
   Add-Result $c.Workstream $c.Id 'NotRequested' $c.Path 'Enable IncludeDefender to collect this dataset.'; continue
  }
  if ($c.GlobalOnly -and -not $profile.CopilotUsageSupported) {
   Add-Result $c.Workstream $c.Id 'UnsupportedCloud' $c.Path 'This Copilot usage API is not available in GCC High. Supply authorized portal evidence if the workload is available.'; continue
  }
  if (-not $graphConnected) { Add-Result $c.Workstream $c.Id 'Failed' $c.Path 'Graph connection unavailable; configuration and usage are unknown.'; continue }
  $path=$c.Path.Replace('{period}',$Period)
  Invoke-ReadCollector $c.Workstream $c.Id $path $c.Explanation { Get-GraphRows -Path $path -Csv:($c.Kind -eq 'Csv') }
 }
 $purview=@(
  @('SensitivityLabels','Get-Label'),@('LabelPolicies','Get-LabelPolicy'),
  @('DlpPolicies','Get-DlpCompliancePolicy'),@('DlpRules','Get-DlpComplianceRule'),
  @('RetentionPolicies','Get-RetentionCompliancePolicy'),@('RetentionRules','Get-RetentionComplianceRule'),
  @('RetentionLabels','Get-ComplianceTag'),@('AutoLabelPolicies','Get-AutoSensitivityLabelPolicy'),
  @('AutoLabelRules','Get-AutoSensitivityLabelRule')
 )
 $purviewReady=$false
 if ($IncludePurview) {
  try {
   Import-Module ExchangeOnlineManagement -ErrorAction Stop
   $p=@{ConnectionUri=$profile.ComplianceUri;AzureADAuthorizationEndpointUri=($profile.Authority+'/organizations');ErrorAction='Stop'}
   if ($Authentication -eq 'Certificate') { $p.AppId=$ClientId;$p.CertificateThumbprint=$CertificateThumbprint;$p.Organization=$Organization }
   elseif ($AdminUPN) { $p.UserPrincipalName=$AdminUPN }
   Connect-IPPSSession @p | Out-Null
   $exchangeConnected=$true; $purviewReady=$true
  } catch { Add-Result 'Connection' 'PurviewConnection' 'Failed' 'Connect-IPPSSession' 'Purview connection failed. Check module and workload-specific RBAC and app permissions.' }
 }
 foreach ($p in $purview) {
  if (-not $purviewReady) {
   $s=if($IncludePurview){'Failed'}else{'NotRequested'}
   Add-Result 'Purview' $p[0] $s $p[1] 'Enable IncludePurview and provision the required Purview roles to collect configuration.'; continue
  }
  $command=$p[1]
  Invoke-ReadCollector 'Purview' $p[0] $command 'Policy/configuration snapshot. Review mode, scope, exclusions and enforcement evidence separately.' { & $command -ErrorAction Stop }
 }
 if ($IncludeSharePoint) {
  try {
   Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell -ErrorAction Stop
   $s=@{Url=$SharePointAdminUrl;AuthenticationUrl=($profile.Authority+'/organizations');ErrorAction='Stop'}
   if ($Authentication -eq 'Certificate') { $s.ClientId=$ClientId;$s.TenantId="$TenantId";$s.CertificateThumbprint=$CertificateThumbprint }
   else { $s.UseSystemBrowser=$true }
   Connect-SPOService @s | Out-Null
   $spoConnected=$true
  } catch { Add-Result 'Connection' 'SharePointConnection' 'Failed' 'Connect-SPOService' 'SharePoint connection failed. Check the admin URL, installed module, certificate support and workload permissions.' }
 }
 foreach ($definition in @(@('SharePoint','SharePointTenant','Get-SPOTenant'),@('SharePoint','SharePointSites','Get-SPOSite'),@('OneDrive','OneDriveSites','Get-SPOSite'))) {
  if (-not $spoConnected) {
   $s=if($IncludeSharePoint){'Failed'}else{'NotRequested'}
   Add-Result $definition[0] $definition[1] $s $definition[2] 'Enable IncludeSharePoint with a valid admin URL and workload permissions.'; continue
  }
  $id=$definition[1]
  Invoke-ReadCollector $definition[0] $id $definition[2] 'Tenant/site configuration inventory. Site inventory does not enumerate item-level access or prove absence of oversharing.' {
   if ($id -eq 'SharePointTenant') { Get-SPOTenant }
   elseif ($id -eq 'OneDriveSites') { Get-SPOSite -IncludePersonalSite $true -Limit All -Detailed | Where-Object Template -like 'SPSPERS*' }
   else { Get-SPOSite -Limit All -Detailed }
  }
 }
 foreach ($c in @($catalog | Where-Object Kind -eq 'Manual')) {
  $inputFile=if($EvidencePath){Join-Path $EvidencePath ($c.Id+'.csv')}else{$null}
  $metadataFile=if($EvidencePath){Join-Path $EvidencePath ($c.Id+'.metadata.json')}else{$null}
  if ($inputFile -and (Test-Path -LiteralPath $inputFile) -and (Test-Path -LiteralPath $metadataFile)) {
   try {
    $meta=Get-Content -LiteralPath $metadataFile -Raw | ConvertFrom-Json
    if ($meta.TenantId -ne "$TenantId" -or $meta.Cloud -ne $Cloud -or -not $meta.Source -or -not $meta.CollectedAtUtc -or -not $meta.Scope) { throw 'Evidence metadata missing or tenant/cloud mismatch.' }
    [void][datetimeoffset]::Parse($meta.CollectedAtUtc)
    $rows=@(Import-Csv -LiteralPath $inputFile)
    Add-Result $c.Workstream $c.Id 'Imported' $meta.Source ($c.Explanation+' Imported evidence collected '+$meta.CollectedAtUtc+'; scope: '+$meta.Scope+'. This import has not been independently validated.') $rows
   } catch { Add-Result $c.Workstream $c.Id 'Failed' $c.Source 'Evidence import failed. Validate CSV and metadata tenant, cloud, source, scope and ISO collection date.' }
  } else { Add-Result $c.Workstream $c.Id 'ManualRequired' $c.Source $c.Explanation }
 }
} finally {
 if ($graphConnected) { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }
 if ($exchangeConnected) { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue }
 if ($spoConnected) { Disconnect-SPOService -ErrorAction SilentlyContinue }
 $manifest.CompletedAtUtc=[datetime]::UtcNow.ToString('o')
 ConvertTo-Json -InputObject $manifest -Depth 30 | Set-Content -LiteralPath (Join-Path $directory 'manifest.json') -Encoding utf8
 Export-SafeCsv -Rows $results.ToArray() -Path (Join-Path $directory 'collection-status.csv')
 Write-AssessmentReport -Manifest ([pscustomobject]$manifest) -Directory $directory
 # One consolidated CSV per workstream retains dataset boundaries and nested payloads.
 foreach ($group in @($results | Group-Object Workstream)) {
  $combined=foreach($r in $group.Group){
   foreach($row in @(Import-Csv -LiteralPath (Join-Path $directory "csv/$($r.Id).csv"))){
    [pscustomobject]@{Dataset=$r.Id;Status=$r.Status;Source=$r.Source;CollectedAtUtc=$r.CollectedAtUtc;Data=($row | ConvertTo-Json -Depth 30 -Compress)}
   }
  }
  Export-SafeCsv -Rows @($combined) -Path (Join-Path $directory "csv/Workstream-$($group.Name).csv")
 }
 Write-Host "Report: $(Join-Path $directory 'Assessment.html')"
 Write-Host 'Review collection-status.csv. No tenant configuration was changed.'
}
