#requires -Version 7.4
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$checks=0
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message};$script:checks++}
function Assert-Throws([scriptblock]$Action,[string]$Pattern){$caught=$false;try{& $Action}catch{$caught=$_.Exception.Message -match $Pattern};Assert $caught "Expected exception: $Pattern"}
Get-ChildItem $root -Recurse -Filter *.ps1|ForEach-Object {$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$t,[ref]$e);Assert ($e.Count -eq 0) "Syntax errors in $($_.Name): $e"}
. (Join-Path $root 'src/Api.ps1')
. (Join-Path $root 'src/Collectors.ps1')
. (Join-Path $root 'src/WorkerSupport.ps1')
. (Join-Path $root 'src/Report.ps1')
$request=[pscustomobject]@{MaxPages=10;MaxRows=100;MaxItems=2;Period='D7';EndUtc=[datetime]::UtcNow.ToString('o')}
$workerRows=[Collections.Generic.List[object]]::new();$workerResults=[Collections.Generic.List[object]]::new()
foreach($uri in @('http://api.fabric.microsoft.com/v1','https://evil.example/v1','https://api.fabric.microsoft.com:444/v1','https://user@api.fabric.microsoft.com/v1','https://api.fabric.microsoft.com/v1#fragment')){Assert-Throws {Assert-ApiUri $uri 'https://api.fabric.microsoft.com'} 'rejected'}
Assert-ApiUri 'https://api.fabric.microsoft.com/v1/a?x=1' 'https://api.fabric.microsoft.com'
$script:call=0
function Invoke-ApiGet($Uri,$Origin){$script:call++;if($script:call -eq 1){[pscustomobject]@{workspaces=@([pscustomobject]@{id=1});continuationToken='a+b'}}else{Assert ($Uri -match 'a%2Bb') 'Continuation encoding';[pscustomobject]@{workspaces=@([pscustomobject]@{id=2})}}}
Read-ApiPages 'https://api.fabric.microsoft.com/v1/admin/workspaces' 'workspaces'
Assert ($workerRows.Count -eq 2) 'Fabric workspaces pagination'
$workerRows.Clear();$script:call=0
function Invoke-ApiGet($Uri,$Origin){[pscustomobject]@{value=@([pscustomobject]@{id=1});continuationUri='https://api.fabric.microsoft.com/v1/a'}}
Assert-Throws {Read-ApiPages 'https://api.fabric.microsoft.com/v1/a'} 'Repeated'
function Invoke-ApiGet($Uri,$Origin){[pscustomobject]@{unexpected=@()}}
Assert-Throws {Read-ApiPages 'https://api.fabric.microsoft.com/v1/a'} 'field'
$workerRows.Clear();$script:call=0
function Invoke-ApiGet($Uri,$Origin){$script:call++;[pscustomobject]@{value=$(if($script:call -eq 1){@([pscustomobject]@{id=1},[pscustomobject]@{id=2})}else{@()})}}
Read-ApiPages 'https://api.security.microsoft.com/api/recommendations?$top=2' 'value' 2
Assert ($script:call -eq 2 -and $workerRows.Count -eq 2) 'Endpoint skip pagination'
$d=[pscustomobject]@{Id='Test';Workstream='Test';Source='Mock';Explanation='Test'}
Invoke-WorkerDataset $d {Add-WorkerRow ([pscustomobject]@{id=1});throw 'HTTP 403'}
Assert ($workerResults[-1].Status -eq 'Incomplete' -and $workerResults[-1].Rows.Count -eq 1) 'Partial data survives failure'
Invoke-WorkerDataset $d {throw 'Access denied'}
Assert ($workerResults[-1].Status -eq 'Failed' -and $workerResults[-1].Rows.Count -eq 0) 'Failed query not empty success'
Invoke-WorkerDataset $d {}
Assert ($workerResults[-1].Status -eq 'Collected' -and $workerResults[-1].Rows.Count -eq 0) 'Valid empty collection'
$request.MaxRows=1
Invoke-WorkerDataset $d {Add-WorkerRow ([pscustomobject]@{id=1});Add-WorkerRow ([pscustomobject]@{id=2})}
Assert ($workerResults[-1].Status -eq 'Incomplete' -and $workerResults[-1].Rows.Count -eq 1) 'Row limit retains data'
$request.MaxRows=100;$script:call=0;$request.Period='D7'
function Export-ActivityExplorerData {
 param($StartTime,$EndTime,$OutputFormat,$PageSize,$Filter1,$PageCookie,$ErrorAction)
 $script:call++
 [pscustomobject]@{ResultData='[{"Id":"a","Activity":"CopilotInteraction","Prompt":"DO NOT EXPORT","Response":"SECRET"}]';LastPage=$true}
}
Invoke-WorkerDataset $d {Read-Activity @('CopilotInteraction')}
Assert ($workerResults[-1].Status -eq 'Collected' -and $script:call -eq 7) 'Activity daily slices'
Assert (($workerResults[-1].Rows|ConvertTo-Json -Depth 10) -notmatch 'DO NOT EXPORT|SECRET') 'Activity content excluded'
$request.Period='D90';$request.MaxPages=40
Invoke-WorkerDataset $d {Read-Activity @('CopilotInteraction')}
Assert ($workerResults[-1].Status -eq 'Incomplete') 'Activity 30-day cap surfaced'
$request.Period='D7';$script:call=0
function Search-UnifiedAuditLog {
 param($StartDate,$EndDate,$Operations,$SessionId,$SessionCommand,$ResultSize,$ErrorAction)
 Assert ($Operations -eq 'CopilotInteraction' -and $SessionCommand -eq 'ReturnLargeSet') 'Audit search scope'
 $script:call++;if($script:call%2){[pscustomobject]@{Identity='1';AuditData='{"Id":"1","Operation":"CopilotInteraction","Prompt":"SECRET"}'}}
}
Invoke-WorkerDataset $d {Read-Audit}
Assert ($workerResults[-1].Status -eq 'Collected' -and $workerResults[-1].Rows.Count -eq 1) 'Audit dedup across overlapping slices'
Assert (($workerResults[-1].Rows|ConvertTo-Json -Depth 10) -notmatch 'SECRET') 'Audit content excluded'
# Verify certificate JWT cryptography without a tenant or certificate-store installation.
$rsa=[Security.Cryptography.RSA]::Create(2048)
$certReq=[Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=OfflineTest',$rsa,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)
$cert=$certReq.CreateSelfSigned([datetimeoffset]::UtcNow.AddMinutes(-1),[datetimeoffset]::UtcNow.AddDays(1))
try {
 $jwt=New-CertificateAssertion $cert '00000000-0000-0000-0000-000000000001' 'https://login.microsoftonline.com/test/oauth2/v2.0/token';$parts=$jwt.Split('.')
 $sig=$parts[2].Replace('-','+').Replace('_','/');$sig=$sig.PadRight($sig.Length+(4-$sig.Length%4)%4,'=')
 Assert ($rsa.VerifyData([Text.Encoding]::UTF8.GetBytes($parts[0]+'.'+$parts[1]),[Convert]::FromBase64String($sig),[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pss)) 'Certificate assertion signature'
}finally{$cert.Dispose();$rsa.Dispose()}
$catalog=@(Get-Content (Join-Path $root 'config/extensions.json') -Raw|ConvertFrom-Json)
Assert (@($catalog.Id|Select-Object -Unique).Count -eq $catalog.Count) 'Unique dataset IDs'
Assert (@($catalog|Where-Object {$_.Id -notmatch '^[A-Za-z0-9_]+$'}).Count -eq 0) 'Safe dataset filenames'
$coverage=@(Get-Content (Join-Path $root 'config/coverage-v2.json') -Raw|ConvertFrom-Json)
Assert ($coverage.Count -eq 20) 'All 20 original review categories retained'
Assert (@($catalog|Where-Object {$_.Workload -in @('Audit','Activity','PowerPlatform') -and $_.Certificate}).Count -eq 0) 'Unverified certificate modes never prompt'
$temp=Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
New-Item -ItemType Directory $temp|Out-Null
try {
 Export-SafeCsv @([pscustomobject]@{Name='=HYPERLINK("bad")';Data='<script>alert(1)</script>'}) (Join-Path $temp 'test.csv')
 $csv=Import-Csv (Join-Path $temp 'test.csv');Assert ($csv.Name.StartsWith("'=")) 'CSV formula escaping'
 Assert ((ConvertTo-HtmlText $csv.Data) -notmatch '<script>') 'HTML escaping'
}finally{Remove-Item $temp -Recurse -Force}
Write-Host "V2 offline checks passed: $checks"
