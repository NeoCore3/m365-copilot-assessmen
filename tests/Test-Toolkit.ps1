#requires -Version 7.4
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
function Assert-True($Condition,$Message){if(-not $Condition){throw $Message}}
foreach($file in Get-ChildItem $root -Recurse -Filter *.ps1){
 $tokens=$null;$errors=$null
 [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 Assert-True ($errors.Count -eq 0) "Parse errors in $($file.Name): $errors"
}
. (Join-Path $root 'src/Report.ps1')
. (Join-Path $root 'src/Graph.ps1')
$temp=Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $temp | Out-Null
try{
 Assert-True ((ConvertTo-SafeCell '=HYPERLINK("x")').StartsWith("'")) 'CSV formula protection failed'
 Assert-True ((ConvertTo-HtmlText '<script>') -eq '&lt;script&gt;') 'HTML escaping failed'
 $csv=Join-Path $temp 'safe.csv'
 Export-SafeCsv @([pscustomobject]@{A='one'},[pscustomobject]@{A='two';B='=1+1'}) $csv
 $read=@(Import-Csv $csv)
 Assert-True ($read[1].B -eq "'=1+1") 'Union CSV schema or formula protection failed'
 $profile=[pscustomobject]@{GraphRoot='https://graph.microsoft.com'}
 $script:call=0
 function Invoke-MgGraphRequest {
  param($Method,$Uri,$OutputType,$OutputFilePath)
  $script:call++
  if($script:call -eq 1){return [pscustomobject]@{value=@([pscustomobject]@{id='one'});'@odata.nextLink'='https://graph.microsoft.com/v1.0/users?page=2'}}
  return [pscustomobject]@{value=@([pscustomobject]@{id='two'})}
 }
 $rows=@(Get-GraphRows '/v1.0/users')
 Assert-True ($rows.Count -eq 2 -and $script:call -eq 2) 'Pagination failed'
 function Invoke-MgGraphRequest {param($Method,$Uri,$OutputType) [pscustomobject]@{value=@();'@odata.nextLink'='https://evil.example/users'}}
 $blocked=$false
 try{Get-GraphRows '/v1.0/users' | Out-Null}catch{$blocked=$true}
 Assert-True $blocked 'Cross-cloud nextLink must be rejected'
 function Invoke-MgGraphRequest {param($Method,$Uri,$OutputType) throw 'Access denied'}
 $failed=$false
 try{Get-GraphRows '/v1.0/users' | Out-Null}catch{$failed=$true}
 Assert-True $failed 'Failed collection must not return a false empty result'
 $directory=$temp
 New-Item -ItemType Directory (Join-Path $temp 'raw') | Out-Null
 function Invoke-MgGraphRequest {
  param($Method,$Uri,$OutputType,$OutputFilePath)
  '"Report Refresh Date","User Principal Name"' + [Environment]::NewLine + '"2026-01-01","user@example.invalid"' | Set-Content $OutputFilePath
 }
 $rows=@(Get-GraphRows '/v1.0/reports/test' -Csv)
 Assert-True ($rows.Count -eq 1) 'CSV response parsing failed'
 # Simulate unavailable Graph module: report must still disclose every gap for all six entry points.
 function Import-Module {param($Name,[switch]$UseWindowsPowerShell,$ErrorAction) throw 'Module intentionally unavailable in test'}
 foreach($cloud in @('Commercial','GCC','GCCHigh')){
  foreach($mode in @('Interactive','Certificate')){
   $folder=if($cloud -eq 'Commercial'){'Commercial'}else{"Government/$cloud"}
   $args=@{TenantId='11111111-1111-1111-1111-111111111111';CustomerName='<script>alert(1)</script>';OutputRoot=$temp}
   if($mode -eq 'Certificate'){$args.ClientId='22222222-2222-2222-2222-222222222222';$args.CertificateThumbprint='DUMMY'}
   & (Join-Path $root "$folder/Start-$mode.ps1") @args
  }
 }
 $reports=@(Get-ChildItem $temp -Recurse -Filter Assessment.html)
 Assert-True ($reports.Count -eq 6) 'Expected six reports'
 foreach($report in $reports){
  $html=Get-Content $report.FullName -Raw
  Assert-True (-not $html.Contains('<h1><script>')) 'Customer name HTML injection'
  Assert-True ($html.Contains('ManualRequired')) 'Missing evidence must be visible'
  $m=Get-Content (Join-Path $report.DirectoryName 'manifest.json') -Raw | ConvertFrom-Json
  Assert-True (@($m.Results | Where-Object Status -eq 'Collected').Count -eq 0) 'Failed auth falsely marked as collected'
  if($m.Cloud -eq 'GCCHigh'){Assert-True (@($m.Results | Where-Object Status -eq 'UnsupportedCloud').Count -ge 1) 'Government capability guard missing'}
 }
 # Requested workloads must preserve connection errors and not suggest enabling an existing switch.
 $args=@{TenantId='11111111-1111-1111-1111-111111111111';CustomerName='Connections';OutputRoot=(Join-Path $temp 'blocked');IncludePurview=$true;IncludeDefender=$true;IncludeSharePoint=$true;SharePointAdminUrl='https://customer-admin.sharepoint.com'}
 & (Join-Path $root 'Commercial/Start-Interactive.ps1') @args
 $mf=Get-ChildItem $args.OutputRoot -Recurse -Filter manifest.json
 $m=Get-Content $mf.FullName -Raw | ConvertFrom-Json
 Assert-True (@($m.Results | Where-Object Status -eq 'BlockedByConnection').Count -ge 27) 'Requested connection failures must block dependent datasets'
 $d=Import-Csv (Join-Path $mf.DirectoryName 'diagnostics.csv')
 Assert-True (@($d | Where-Object Message -match 'intentionally unavailable').Count -eq 4) 'All four original connection errors must be retained'
 Assert-True (@($m.Results | Where-Object { $_.Status -eq 'BlockedByConnection' -and $_.Explanation -match 'Enable Include' }).Count -eq 0) 'Misleading enable guidance returned'

 $connectionCapture=@{}
 # Purview failure and Graph failure must not prevent independent Defender collection.
 function Import-Module {param($Name,[switch]$UseWindowsPowerShell,$ErrorAction)}
 function Connect-MgGraph {throw 'Graph test connection failed'}
 function Connect-IPPSSession {throw 'Purview test failure access_token=secret123 Bearer abc123'}
 function Connect-ExchangeOnline {param($ExchangeEnvironmentName,$ShowBanner,$ErrorAction) $connectionCapture.exchangeEnvironment=$ExchangeEnvironmentName}
 function Disconnect-ExchangeOnline {param($Confirm,$ErrorAction) throw 'Disconnect test failure'}
 $defenderNames=@('AntiPhishPolicy','AntiPhishRule','SafeLinksPolicy','SafeLinksRule','SafeAttachmentPolicy','SafeAttachmentRule','HostedContentFilterPolicy','HostedContentFilterRule','MalwareFilterPolicy','MalwareFilterRule','HostedOutboundSpamFilterPolicy','HostedOutboundSpamFilterRule','AtpPolicyForO365','ATPProtectionPolicyRule','EOPProtectionPolicyRule')
 foreach($name in $defenderNames){Set-Item -Path "function:Get-$name" -Value {param($ErrorAction) [pscustomobject]@{Name='Test policy';Enabled=$true}}}
 function Get-SafeLinksRule {param($ErrorAction) throw 'Access denied test'}
 foreach($cloud in @('Commercial','GCC','GCCHigh')){
  $folder=if($cloud -eq 'Commercial'){'Commercial'}else{"Government/$cloud"}
  $args=@{TenantId='11111111-1111-1111-1111-111111111111';CustomerName='Mixed';OutputRoot=(Join-Path $temp "mixed-$cloud");IncludePurview=$true;IncludeDefender=$true}
  & (Join-Path $root "$folder/Start-Interactive.ps1") @args
  $mf=Get-ChildItem $args.OutputRoot -Recurse -Filter manifest.json
  $m=Get-Content $mf.FullName -Raw | ConvertFrom-Json
  Assert-True (@($m.Results | Where-Object { $_.Workstream -eq 'Defender' -and $_.Status -eq 'Collected' }).Count -eq 14) 'Independent Defender policy collection failed'
  Assert-True (($m.Results | Where-Object Id -eq 'DefenderSafeLinksRule').Status -eq 'Failed') 'Single command failure was not isolated'
  Assert-True (($m.Results | Where-Object Id -eq 'SensitivityLabels').Status -eq 'BlockedByConnection') 'Purview failure did not block its datasets'
  $expected=if($cloud -eq 'GCCHigh'){'O365USGovGCCHigh'}else{'O365Default'}
  Assert-True ($connectionCapture.exchangeEnvironment -eq $expected) 'Defender cloud routing failed'
  $diag=Get-Content (Join-Path $mf.DirectoryName 'diagnostics.csv') -Raw
  Assert-True ($diag -notmatch 'secret123|abc123') 'Diagnostic credentials not redacted'
  Assert-True ($diag -match 'Disconnect test failure') 'Disconnect failure must not prevent report output'
 }
 # Successful Purview connection: one unavailable cmdlet must not hide other configuration.
 function Connect-IPPSSession {
  param($ConnectionUri,$AzureADAuthorizationEndpointUri,$AppId,$CertificateThumbprint,$Organization,$ErrorAction,[switch]$DisableWAM)
  $connectionCapture.complianceUri=$ConnectionUri; $connectionCapture.authority=$AzureADAuthorizationEndpointUri
  $connectionCapture.ippsApp=$AppId; $connectionCapture.ippsOrganization=$Organization
 }
 function Connect-ExchangeOnline {
  param($ExchangeEnvironmentName,$ShowBanner,$AppId,$CertificateThumbprint,$Organization,$ErrorAction)
  $connectionCapture.exoApp=$AppId; $connectionCapture.exoOrganization=$Organization
 }
 foreach($name in @('Label','LabelPolicy','DlpCompliancePolicy','DlpComplianceRule','RetentionCompliancePolicy','RetentionComplianceRule','ComplianceTag','AutoSensitivityLabelPolicy')){
  Set-Item -Path "function:Get-$name" -Value {param($ErrorAction) [pscustomobject]@{Name='Test Purview policy'}}
 }
 function Get-AutoSensitivityLabelRule {param($ErrorAction) throw [System.Management.Automation.CommandNotFoundException]::new('Command unavailable test')}
 foreach($cloud in @('Commercial','GCC','GCCHigh')){
  $folder=if($cloud -eq 'Commercial'){'Commercial'}else{"Government/$cloud"}
  $args=@{TenantId='11111111-1111-1111-1111-111111111111';CustomerName='Certificate';OutputRoot=(Join-Path $temp "cert-$cloud");IncludePurview=$true;IncludeDefender=$true;ClientId='22222222-2222-2222-2222-222222222222';CertificateThumbprint='DUMMY';Organization='customer.onmicrosoft.com'}
  & (Join-Path $root "$folder/Start-Certificate.ps1") @args
  $mf=Get-ChildItem $args.OutputRoot -Recurse -Filter manifest.json
  $m=Get-Content $mf.FullName -Raw | ConvertFrom-Json
  Assert-True (@($m.Results | Where-Object { $_.Workstream -eq 'Purview' -and $_.Status -eq 'Collected' }).Count -eq 8) 'Purview collection failed after successful connection'
  Assert-True (($m.Results | Where-Object Id -eq 'AutoLabelRules').Status -eq 'CommandUnavailable') 'Unavailable cmdlet must be distinguished'
  Assert-True ($connectionCapture.ippsApp -eq $args.ClientId -and $connectionCapture.exoApp -eq $args.ClientId -and $connectionCapture.ippsOrganization -eq $args.Organization -and $connectionCapture.exoOrganization -eq $args.Organization) 'Certificate workload arguments not forwarded'
  if($cloud -eq 'GCCHigh'){
   Assert-True ($connectionCapture.complianceUri -eq 'https://ps.compliance.protection.office365.us/powershell-liveid/' -and $connectionCapture.authority -eq 'https://login.microsoftonline.us/organizations') 'Government Purview endpoint routing failed'
  }else{Assert-True (-not $connectionCapture.complianceUri -and -not $connectionCapture.authority) 'Commercial/GCC should use default Purview endpoints'}
 }
 Write-Host 'PASS: parser, CSV safety, HTML escaping, paging, cloud isolation, error propagation and six entry-point failure reports.'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
