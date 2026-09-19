# Error summaries deliberately exclude invocation text, request headers and full ErrorRecord dumps.
function Protect-AssessmentDiagnostic {
 param([string]$Text)
 $Text=$Text -replace '(?i)Bearer\s+[^\s,;]+','Bearer [REDACTED]'
 $Text=$Text -replace '(?i)((?:access_token|refresh_token|id_token|client_secret|client_assertion|password)\s*["'']?\s*[:=]\s*["'']?)[^\s"'',;&]+','$1[REDACTED]'
 $Text=$Text -replace '\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b','[REDACTED JWT]'
 return $Text
}
function Add-AssessmentDiagnostic {
 param([string]$Id,[string]$Source,[System.Management.Automation.ErrorRecord]$Record)
 $message=Protect-AssessmentDiagnostic ($Record.Exception.Message)
 $hint='Check the service error, tenant/cloud, module version, workload RBAC and service availability. A failed query is not an empty dataset.'
 if ($Record.Exception -is [System.Management.Automation.CommandNotFoundException]) {
  $hint='The command is not available in this session. Check module version, service/cloud support and the effective workload RBAC that controls imported commands.'
 } elseif ($message -match 'AADSTS65001|consent_required|admin.*consent') {
  $hint='Customer administrator consent is required for the requested application permissions. Workload RBAC is separate.'
 } elseif ($message -match 'AADSTS53003|Conditional Access') {
  $hint='Customer Conditional Access blocked sign-in. Ask the customer to review the matching Entra sign-in log; do not bypass the policy.'
 } elseif ($message -match 'WAM|window handle|0x80070520') {
  $hint='Possible WAM sign-in issue. Use a fresh PowerShell window as the signed-in Windows user. If confirmed, use the documented opt-in DisableWAM switch with a supporting ExchangeOnlineManagement version.'
 }
 $modules=@(Get-Module -Name Microsoft.Graph.Authentication,ExchangeOnlineManagement,Microsoft.Online.SharePoint.PowerShell | ForEach-Object { $_.Name+' '+$_.Version }) -join '; '
 $diagnostics.Add([pscustomobject]@{
  Id=$Id;Source=$Source;CollectedAtUtc=[datetime]::UtcNow.ToString('o')
  ErrorType=$Record.Exception.GetType().FullName
  ErrorId=(Protect-AssessmentDiagnostic $Record.FullyQualifiedErrorId)
  Message=$message;Guidance=$hint;PowerShellVersion="$($PSVersionTable.PSVersion)";LoadedModules=$modules
 })
 return "$message $hint See diagnostics.csv ($Id)."
}
function Set-AssessmentWamOption {
 param([hashtable]$Parameters,[string]$Command)
 if ($DisableWAM -and $Authentication -eq 'Interactive') {
  if (-not (Get-Command $Command -ErrorAction Stop).Parameters.ContainsKey('DisableWAM')) {
   throw "$Command does not support DisableWAM in the loaded module. Update ExchangeOnlineManagement in a fresh session or omit DisableWAM."
  }
  $Parameters.DisableWAM=$true
 }
}
