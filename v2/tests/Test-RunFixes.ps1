#requires -Version 7.4
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/EvidenceQuality.ps1')
. (Join-Path $root 'src/Collectors.ps1')
. (Join-Path $root 'src/WorkerSupport.ps1')
$checks=0
function Check($Condition,$Message){if(-not $Condition){throw $Message};$script:checks++}
$expected=[datetimeoffset]::Parse('2026-09-22T01:25:20.6421434Z').UtcDateTime
$json='{"EndUtc":"2026-09-22T01:25:20.6421434Z"}'|ConvertFrom-Json
foreach($inputDate in @($json.EndUtc,$expected,[datetimeoffset]$expected,'2026-09-21T19:25:20.6421434-06:00')){
 $actual=ConvertTo-AssessmentUtc $inputDate
 Check ($actual.Ticks -eq $expected.Ticks -and $actual.Kind -eq [DateTimeKind]::Utc) 'UTC offset changed during conversion'
}
$bad=$false;try{ConvertTo-AssessmentUtc ([datetime]::SpecifyKind($expected,[DateTimeKind]::Unspecified))}catch{$bad=$true};Check $bad 'Ambiguous timestamp accepted'
$bad=$false;try{ConvertTo-AssessmentUtc '2026-09-22T01:25:20'}catch{$bad=$true};Check $bad 'Unzoned string accepted'
$old=[pscustomobject]@{Parameters=@{};Module=[pscustomobject]@{Version=[version]'7.7.0'}}
$r=[pscustomobject]@{TenantId='test';Authentication='Interactive';DisableWAM=$true}
$p=Get-AssessmentTeamsParameters $old $r
Check (-not $p.ContainsKey('DisableWAM')) 'Older Teams forced to use unsupported WAM parameter'
$modern=[pscustomobject]@{Parameters=@{DisableWAM=$null};Module=[pscustomobject]@{Version=[version]'7.8.1'}}
$p=Get-AssessmentTeamsParameters $modern $r;Check $p.DisableWAM 'Modern Teams WAM option missing'
$fallback=[pscustomobject]@{Parameters=@{UseDeviceAuthentication=$null};Module=[pscustomobject]@{Version=[version]'9.0.0'}}
$p=Get-AssessmentTeamsParameters $fallback $r;Check $p.UseDeviceAuthentication 'Device-code alternative missing'
$r.Authentication='Certificate';$r|Add-Member ClientId test;$r|Add-Member CertificateThumbprint test
$p=Get-AssessmentTeamsParameters $old $r;Check (-not $p.ContainsKey('UseDeviceAuthentication') -and -not $p.ContainsKey('DisableWAM')) 'Certificate mode fell back to user authentication'
$q=@(Get-ReportIdentityQuality 'Usage' @([pscustomobject]@{'User Principal Name'=('A'*32);'Site URL'=''}))
Check ($q.Count -eq 2 -and $q[0].ConcealedFormat -eq 1 -and $q[1].Blank -eq 1) 'Concealed/blank identities not detected'
$q=@(Get-ReportIdentityQuality 'Usage' @([pscustomobject]@{'User Principal Name'='reader@example.invalid';'Site URL'='https://example.sharepoint.com'}))
Check ($q[0].ConcealedFormat -eq 0 -and $q[1].Blank -eq 0) 'Clear identities misclassified'
$request=[pscustomobject]@{MaxPages=40;MaxRows=1000;MaxItems=5;Period='D90';EndUtc=[datetime]::UtcNow.AddMinutes(-10)}
$workerRows=[Collections.Generic.List[object]]::new();$workerResults=[Collections.Generic.List[object]]::new()
$d=[pscustomobject]@{Id='Activity';Workstream='Purview';Source='Mock';Explanation='Metadata'}
function Export-ActivityExplorerData {
 param($StartTime,$EndTime,$OutputFormat,$PageSize,$Filter1,$PageCookie,$ErrorAction)
 Check ($StartTime.Kind -eq [DateTimeKind]::Utc -and $EndTime.Kind -eq [DateTimeKind]::Utc) 'Activity query lost UTC Kind'
 Check ($EndTime -le [datetime]::UtcNow -and $StartTime -gt [datetime]::UtcNow.AddDays(-30)) 'Activity query outside retention window'
 [pscustomobject]@{ResultData='[{"RecordIdentity":"event-1","Happened":"2026-09-21T01:00:00Z","Activity":"DLP rule matched","User":"reader@example.invalid","RuleName":"Example","FullUrl":"https://example.sharepoint.com/a","Subject":"DO NOT EXPORT","EntityProperties":{"Prompt":"SECRET"}}]';LastPage=$true}
}
Invoke-WorkerDataset $d {Read-Activity @('DLPRuleMatch')}
$res=$workerResults[-1]
Check ($res.Status -eq 'Incomplete' -and $res.Rows.Count -eq 1) 'D90 limit/dedup not represented'
Check ($res.Rows[0].RecordIdentity -eq 'event-1' -and $res.Rows[0].Happened -and $res.Rows[0].RuleName -eq 'Example' -and $res.Rows[0].FullUrl) 'Documented metadata fields dropped'
Check (($res.Rows|ConvertTo-Json -Depth 10) -notmatch 'DO NOT EXPORT|SECRET') 'Free-form content leaked'
function Get-SPODataAccessGovernanceInsight {param($ReportEntity,$Workload,$ErrorAction);Check (-not $PSBoundParameters.ContainsKey('Workload')) 'Both-workload report incorrectly filtered'}
$d=[pscustomobject]@{Id='DAG';Workstream='SharePoint';Source='Mock';Explanation='Existing reports';Entity='Everyone';SpoWorkload='Both'}
Invoke-WorkerDataset $d {Read-Dag $d}
Check ($workerResults[-1].Status -eq 'NoExistingReport') 'Missing report mislabeled as failure or successful zero'
$catalog=@(Get-Content (Join-Path $root 'config/extensions.json') -Raw|ConvertFrom-Json)
Check (@($catalog|Where-Object {$_.Entity -eq 'SensitivityLabelForFiles' -and $_.SpoWorkload -eq 'OneDriveForBusiness'}).Count -eq 0) 'Unsupported OneDrive sensitivity query exists'
Check (@($catalog|Where-Object {$_.Entity -in @('Everyone','EveryoneExceptExternalUsers')}).Count -eq 2) 'Duplicate combined-workload DAG queries'
Check (@($catalog|Where-Object CoreSPO).Count -eq 3) 'Core SPO not routed to isolated worker'
Write-Host "Run-defect regression checks passed: $checks; time zone: $([TimeZoneInfo]::Local.Id)"
