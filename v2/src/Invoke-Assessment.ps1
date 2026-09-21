#requires -Version 7.4
[CmdletBinding()]
param(
 [Parameter(Mandatory)][guid]$TenantId,
 [Parameter(Mandatory)][string]$CustomerName,
 [Parameter(Mandatory)][ValidateSet('Commercial','GCC','GCCHigh')][string]$Cloud,
 [Parameter(Mandatory)][ValidateSet('Interactive','Certificate')][string]$Authentication,
 [string]$ClientId, [string]$CertificateThumbprint, [string]$Organization, [string]$AdminUPN,
 [string]$SharePointAdminUrl,
 [ValidateSet('D7','D30','D90','D180')][string]$Period='D90',
 [string]$OutputRoot=(Join-Path $env:LOCALAPPDATA 'M365AssessmentV2'),
 [string]$EvidencePath,
 [switch]$IncludePurview, [switch]$IncludeSharePoint, [switch]$IncludeDefender,
 [switch]$IncludeFabric, [switch]$IncludeDAG, [switch]$IncludeTeamsPolicies,
 [switch]$IncludePowerPlatform, [switch]$IncludeAudit, [switch]$IncludeActivityExplorer,
 [switch]$IncludeAgents, [switch]$IncludeAgentRegistryPreview, [switch]$IncludeEndpoint,
 [switch]$IncludeItemPermissions,
 [string]$ApiClientId, [string[]]$DataverseUrls, [string[]]$DriveIds,
 [ValidateRange(1,10000)][int]$MaxPages=200,
 [ValidateRange(1,1000000)][int]$MaxRows=100000,
 [ValidateRange(1,100000)][int]$MaxItems=1000,
 [switch]$DisableWAM
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Report.ps1')
$root = Split-Path $PSScriptRoot -Parent
$profile = Get-Content (Join-Path $root "config/$Cloud.json") -Raw | ConvertFrom-Json
$catalog = @(Get-Content (Join-Path $root 'config/collectors.json') -Raw | ConvertFrom-Json)
if ($Authentication -eq 'Certificate' -and (-not $ClientId -or -not $CertificateThumbprint)) { throw 'Certificate mode requires ClientId and CertificateThumbprint.' }
if ($Authentication -eq 'Certificate' -and ($IncludePurview -or $IncludeDefender) -and -not $Organization) { throw 'Purview/Defender certificate mode requires the tenant initial Organization domain.' }
if ($IncludeSharePoint) {
 $uri = [uri]$SharePointAdminUrl
 if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or -not $uri.Host.EndsWith($profile.SharePointSuffix) -or $uri.Host -notmatch '-admin\.sharepoint\.') { throw 'Provide the correct HTTPS SharePoint admin URL for the selected cloud.' }
}
# Unique run folders prevent stale data being mistaken for a current collection.
$runId = [datetime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$directory = Join-Path $OutputRoot "$Cloud-$TenantId-$runId"
foreach ($d in @($directory,(Join-Path $directory 'raw'),(Join-Path $directory 'csv'))) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
$results = [System.Collections.Generic.List[object]]::new()
$diagnostics = [System.Collections.Generic.List[object]]::new()
. (Join-Path $PSScriptRoot 'Diagnostics.ps1')
. (Join-Path $PSScriptRoot 'WorkloadPrerequisites.ps1')
$manifest = [ordered]@{SchemaVersion='2.0';ToolkitVersion='2.0.0-preview.1';BaselineCommit='dc684d38c8ab5f2b73f8a388178f6ef89826c72d';CustomerName=$CustomerName;TenantId="$TenantId";Cloud=$Cloud;Authentication=$Authentication;Period=$Period;CollectedAtUtc=[datetime]::UtcNow.ToString('o');Results=$results}
function Add-Result {
 param([string]$Workstream,[string]$Id,[string]$Status,[string]$Source,[string]$Explanation,[object[]]$Rows=@())
 $Rows = @($Rows | Where-Object { $null -ne $_ })
 if ($Status -in @('Collected','Imported','Incomplete','Derived')) {
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
 catch {
  $detail=Add-AssessmentDiagnostic -Id $Id -Source $Source -Record $_
  $status=if($_.Exception -is [System.Management.Automation.CommandNotFoundException]){'CommandUnavailable'}else{'Failed'}
  Add-Result $Workstream $Id $status $Source ($Explanation + ' ' + $detail)
 }
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
  $detail=Add-AssessmentDiagnostic 'GraphConnection' 'Connect-MgGraph' $_
  Add-Result 'Connection' 'GraphConnection' 'Failed' 'Connect-MgGraph' $detail
 }
 foreach ($c in @($catalog | Where-Object Kind -ne 'Manual')) {
  if ($c.Workstream -eq 'Defender' -and -not $IncludeDefender) {
   Add-Result $c.Workstream $c.Id 'NotRequested' $c.Path 'Enable IncludeDefender to collect this dataset.'; continue
  }
  if ($c.GlobalOnly -and -not $profile.CopilotUsageSupported) {
   Add-Result $c.Workstream $c.Id 'UnsupportedCloud' $c.Path 'This Copilot usage API is not available in GCC High. Supply authorized portal evidence if the workload is available.'; continue
  }
  if (-not $graphConnected) { Add-Result $c.Workstream $c.Id 'BlockedByConnection' $c.Path 'Graph connection failed. See GraphConnection in diagnostics.csv; configuration and usage are unknown.'; continue }
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
   $p=@{ErrorAction='Stop'}
   if ($Cloud -eq 'GCCHigh') { $p.ConnectionUri=$profile.ComplianceUri; $p.AzureADAuthorizationEndpointUri=$profile.Authority+'/organizations' }
   Set-AssessmentWamOption -Parameters $p -Command 'Connect-IPPSSession'
   if ($Authentication -eq 'Certificate') { $p.AppId=$ClientId;$p.CertificateThumbprint=$CertificateThumbprint;$p.Organization=$Organization }
   elseif ($AdminUPN) { $p.UserPrincipalName=$AdminUPN }
   Connect-IPPSSession @p | Out-Null
   $exchangeConnected=$true; $purviewReady=$true
  } catch {
   $detail=Add-AssessmentDiagnostic 'PurviewConnection' 'Connect-IPPSSession' $_
   Add-Result 'Connection' 'PurviewConnection' 'Failed' 'Connect-IPPSSession' $detail
  }
 }
 foreach ($p in $purview) {
  if (-not $purviewReady) {
   $s=if($IncludePurview){'BlockedByConnection'}else{'NotRequested'}
   $why=if($IncludePurview){'Purview connection failed. See PurviewConnection in diagnostics.csv.'}else{'Enable IncludePurview to request this dataset.'}
   Add-Result 'Purview' $p[0] $s $p[1] $why; continue
  }
  $command=$p[1]
  Invoke-ReadCollector 'Purview' $p[0] $command 'Policy/configuration snapshot. Review mode, scope, exclusions and enforcement evidence separately.' { & $command -ErrorAction Stop }
 }
 if ($IncludeSharePoint) {
  try {
   Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell -ErrorAction Stop
   $spoCommand=Get-Command Connect-SPOService -ErrorAction Stop
   $s=Get-AssessmentSpoParameters -Command $spoCommand -Url $SharePointAdminUrl -Cloud $Cloud -Authority $profile.Authority -Authentication $Authentication -ClientId $ClientId -TenantId "$TenantId" -CertificateThumbprint $CertificateThumbprint
   Connect-SPOService @s | Out-Null
   $spoConnected=$true
  } catch {
   $detail=Add-AssessmentDiagnostic 'SharePointConnection' 'Connect-SPOService' $_
   Add-Result 'Connection' 'SharePointConnection' 'Failed' 'Connect-SPOService' $detail
  }
 }
 foreach ($definition in @(@('SharePoint','SharePointTenant','Get-SPOTenant'),@('SharePoint','SharePointSites','Get-SPOSite'),@('OneDrive','OneDriveSites','Get-SPOSite'))) {
  if (-not $spoConnected) {
   $s=if($IncludeSharePoint){'BlockedByConnection'}else{'NotRequested'}
   $why=if($IncludeSharePoint){'SharePoint connection failed. See SharePointConnection in diagnostics.csv.'}else{'Enable IncludeSharePoint with a valid admin URL to request this dataset.'}
   Add-Result $definition[0] $definition[1] $s $definition[2] $why; continue
  }
  $id=$definition[1]
  Invoke-ReadCollector $definition[0] $id $definition[2] 'Tenant/site configuration inventory. Site inventory does not enumerate item-level access or prove absence of oversharing.' {
   if ($id -eq 'SharePointTenant') { Get-SPOTenant }
   elseif ($id -eq 'OneDriveSites') { Get-SPOSite -IncludePersonalSite $true -Limit All -Detailed | Where-Object Template -like 'SPSPERS*' }
   else { Get-SPOSite -Limit All -Detailed }
  }
 }
 # Defender for Office 365 configuration uses Exchange Online, independently of Graph and Purview.
 $defenderReady=$false
 $defenderCommands=@(
  'Get-AntiPhishPolicy','Get-AntiPhishRule',
  'Get-SafeLinksPolicy','Get-SafeLinksRule',
  'Get-SafeAttachmentPolicy','Get-SafeAttachmentRule',
  'Get-HostedContentFilterPolicy','Get-HostedContentFilterRule',
  'Get-MalwareFilterPolicy','Get-MalwareFilterRule',
  'Get-HostedOutboundSpamFilterPolicy','Get-HostedOutboundSpamFilterRule',
  'Get-AtpPolicyForO365','Get-ATPProtectionPolicyRule','Get-EOPProtectionPolicyRule'
 )
 if ($IncludeDefender) {
  try {
   Import-Module ExchangeOnlineManagement -ErrorAction Stop
   $e=@{ExchangeEnvironmentName=$profile.ExchangeEnvironment;ShowBanner=$false;ErrorAction='Stop'}
   Set-AssessmentWamOption -Parameters $e -Command 'Connect-ExchangeOnline'
   if ($Authentication -eq 'Certificate') { $e.AppId=$ClientId; $e.CertificateThumbprint=$CertificateThumbprint; $e.Organization=$Organization }
   elseif ($AdminUPN) { $e.UserPrincipalName=$AdminUPN }
   Connect-ExchangeOnline @e | Out-Null
   $exchangeConnected=$true; $defenderReady=$true
  } catch {
   $detail=Add-AssessmentDiagnostic 'DefenderConnection' 'Connect-ExchangeOnline' $_
   Add-Result 'Connection' 'DefenderConnection' 'Failed' 'Connect-ExchangeOnline' $detail
  }
 }
 foreach ($command in $defenderCommands) {
  $id='Defender'+$command.Substring(4)
  if (-not $defenderReady) {
   $s=if($IncludeDefender){'BlockedByConnection'}else{'NotRequested'}
   $why=if($IncludeDefender){'Exchange Online connection failed. See DefenderConnection in diagnostics.csv.'}else{'Enable IncludeDefender to request this dataset.'}
   Add-Result 'Defender' $id $s $command $why
   continue
  }
  Invoke-ReadCollector 'Defender' $id $command 'Defender for Office 365/EOP configuration. Evaluate policies with rules, priorities, recipients, exclusions and preset policies; this is not effectiveness or incident evidence.' { & $command -ErrorAction Stop }
 }
 . (Join-Path $PSScriptRoot 'Extensions.ps1')
 Invoke-AssessmentExtensions
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
  } else {
   $coverage=@($extensionCoverage | Where-Object Group -eq $c.Id)
   $ids=@($coverage | ForEach-Object Datasets)
   $children=@($results | Where-Object { $_.Id -in $ids })
   $status=if(@($children | Where-Object Status -in @('Collected','Derived','Incomplete')).Count){'PartialCoverage'}else{'EvidenceRequired'}
   $note=if($coverage.Count){$coverage[0].Remaining}else{$c.Explanation}
   Add-Result $c.Workstream $c.Id $status $c.Source ($note+' Automated datasets: '+($ids -join ', ')+'. Review their individual statuses; this category is not fully validated.')
  }
 }
} finally {
 if ($graphConnected) { try { Disconnect-MgGraph -ErrorAction Stop | Out-Null } catch { [void](Add-AssessmentDiagnostic 'GraphDisconnect' 'Disconnect-MgGraph' $_) } }
 if ($exchangeConnected) { try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction Stop } catch { [void](Add-AssessmentDiagnostic 'ExchangeDisconnect' 'Disconnect-ExchangeOnline' $_) } }
 if ($spoConnected) { try { Disconnect-SPOService -ErrorAction Stop } catch { [void](Add-AssessmentDiagnostic 'SharePointDisconnect' 'Disconnect-SPOService' $_) } }
 Export-SafeCsv -Rows $diagnostics.ToArray() -Path (Join-Path $directory 'diagnostics.csv')
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
 Write-Host 'Review collection-status.csv and diagnostics.csv. No tenant configuration was changed.'
}
