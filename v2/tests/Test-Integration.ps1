#requires -Version 7.4
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$repo=Split-Path $root -Parent
$hashes=Get-Content (Join-Path $root 'config/baseline-hashes.json') -Raw|ConvertFrom-Json -AsHashtable
foreach($file in $hashes.Keys){if((Get-FileHash (Join-Path $repo $file) -Algorithm SHA256).Hash -ne $hashes[$file]){throw "Original version changed: $file"}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString());New-Item -ItemType Directory $temp|Out-Null
$oldModulePath=$env:PSModulePath
try {
 # Child workers cannot discover installed cloud modules, so this integration test cannot sign in.
 $env:PSModulePath=Join-Path $PSHOME 'Modules'
 $exe=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
 foreach($cloud in @('Commercial','GCC','GCCHigh')){
  foreach($auth in @('Interactive','Certificate')){
   $wrapper=if($cloud -eq 'Commercial'){"Commercial/Start-$auth.ps1"}else{"Government/$cloud/Start-$auth.ps1"}
   $spo=if($cloud -eq 'GCCHigh'){'https://offline-admin.sharepoint.us'}else{'https://offline-admin.sharepoint.com'}
   $args=@('-NoProfile','-File',(Join-Path $root $wrapper),'-TenantId','00000000-0000-0000-0000-000000000001','-CustomerName','OfflineTest','-ClientId','00000000-0000-0000-0000-000000000002','-CertificateThumbprint',('0'*40),'-Organization','offline.onmicrosoft.com','-SharePointAdminUrl',$spo,'-OutputRoot',$temp,'-IncludePurview','-IncludeDefender','-IncludeSharePoint','-IncludeFabric','-IncludeDAG','-IncludeTeamsPolicies','-IncludePowerPlatform','-IncludeAudit','-IncludeActivityExplorer','-IncludeAgents','-IncludeAgentRegistryPreview','-IncludeEndpoint','-IncludeItemPermissions')
   & $exe @args|Out-Null
   if($LASTEXITCODE -ne 0){throw "Launcher failed: $cloud/$auth"}
  }
 }
 $manifests=@(Get-ChildItem $temp -Recurse -Filter manifest.json)
 if($manifests.Count -ne 6){throw 'Expected six isolated reports.'}
 foreach($file in $manifests){
  $m=Get-Content $file.FullName -Raw|ConvertFrom-Json
  if($m.ToolkitVersion -ne '2.0.0-preview.1'){throw 'Missing toolkit version.'}
  if(@($m.Results.Id|Select-Object -Unique).Count -ne $m.Results.Count){throw 'Duplicate dataset result.'}
  if(@($m.Results|Where-Object {$_.Status -eq 'Collected'}).Count){throw 'Missing module test reported collected data.'}
  $fabric=$m.Results|Where-Object Id -eq 'FabricTenantSettings'
  if($m.Cloud -eq 'Commercial'){
   if($fabric.Status -ne 'BlockedByConnection'){throw 'Fabric failure not correctly represented.'}
   if($m.Authentication -eq 'Certificate' -and ($m.Results|Where-Object Id -eq 'CopilotAuditActivity').Status -ne 'AuthenticationUnverified'){throw 'Unattended audit attempted.'}
  }elseif($fabric.Status -ne 'CapabilityUnverified'){throw 'Government capability guard failed.'}
  if(-not (Test-Path (Join-Path $file.DirectoryName 'Assessment.html'))){throw 'Missing final HTML.'}
  if(-not (Test-Path (Join-Path $file.DirectoryName 'coverage-v2.csv'))){throw 'Missing coverage index.'}
 }
 if(@(Get-ChildItem $temp -Recurse -Filter request.json).Count){throw 'Worker request files not removed.'}
 Write-Host 'V2 integration passed: 6 launchers, original-file preservation, isolated failure reports, cloud/auth guards.'
}finally{$env:PSModulePath=$oldModulePath;Remove-Item $temp -Recurse -Force}
