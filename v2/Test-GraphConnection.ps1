#requires -Version 7.4
[CmdletBinding()]
param(
 [Parameter(Mandatory)][guid]$TenantId,
 [ValidateSet('Commercial','GCC','GCCHigh')][string]$Cloud='Commercial',
 [ValidateSet('Browser','DeviceCode')][string]$GraphAuthMode='Browser',
 [string]$ClientId,
 [string]$GraphModuleVersion='2.40.0'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'src/Runtime.ps1')
. (Join-Path $PSScriptRoot 'src/Diagnostics.ps1')
$profile=Get-Content (Join-Path $PSScriptRoot "config/$Cloud.json") -Raw|ConvertFrom-Json
$catalog=Get-Content (Join-Path $PSScriptRoot 'config/collectors.json') -Raw|ConvertFrom-Json
try{
 Import-AssessmentGraph $GraphModuleVersion
 $p=@{TenantId="$TenantId";Environment=$profile.GraphEnvironment;ContextScope='Process';NoWelcome=$true;ErrorAction='Stop';Scopes=@($catalog|Where-Object {$_.Permission -and ($Cloud -ne 'GCCHigh' -or -not $_.GlobalOnly)}|Select-Object -ExpandProperty Permission -Unique)}
 if($ClientId){$p.ClientId=$ClientId}
 if($GraphAuthMode -eq 'DeviceCode'){$p.UseDeviceCode=$true}
 Connect-AssessmentGraphSession $p
 $ctx=Get-MgContext
 if($ctx.TenantId -ne "$TenantId" -or $ctx.Environment -ne $profile.GraphEnvironment){throw 'Graph tenant/cloud mismatch.'}
 Write-Host "PASS: Graph authenticated for tenant $($ctx.TenantId), account $($ctx.Account), environment $($ctx.Environment)."
 Write-Host 'This checks authentication for the core scopes only; it does not validate every API or workload. The assessment will sign in separately.'
}catch{
 Write-Host ('GRAPH SIGN-IN FAILED: '+(Protect-AssessmentDiagnostic $_.Exception.Message)) -ForegroundColor Red
 Write-Host 'Capture this error text (not any device code). No full assessment was started.'
 exit 1
}finally{
 if(Get-Command Disconnect-MgGraph -ErrorAction SilentlyContinue){try{Disconnect-MgGraph -ErrorAction Stop|Out-Null}catch{}}
}
