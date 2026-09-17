#requires -Version 7.2
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
 Write-Host 'PASS: parser, CSV safety, HTML escaping, paging, cloud isolation, error propagation and six entry-point failure reports.'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
