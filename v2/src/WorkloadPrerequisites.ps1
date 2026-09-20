# Inspect the imported command: Windows compatibility proxies can report version 1.0
# regardless of the underlying SharePoint binary's version.
function Get-AssessmentSpoParameters {
 param(
  [System.Management.Automation.CommandInfo]$Command,
  [string]$Url,[string]$Cloud,[string]$Authority,
  [string]$Authentication,[string]$ClientId,[string]$TenantId,[string]$CertificateThumbprint
 )
 $p=@{Url=$Url;ErrorAction='Stop'}
 if ($Authentication -eq 'Certificate') {
  foreach($name in @('ClientId','TenantId','CertificateThumbprint')) {
   if (-not $Command.Parameters.ContainsKey($name)) {
    throw "SharePoint prerequisite: loaded Connect-SPOService lacks certificate parameter $name. Update Microsoft.Online.SharePoint.PowerShell in Windows PowerShell 5.1 and restart pwsh. Certificate mode will not fall back to interactive sign-in."
   }
  }
  $p.ClientId=$ClientId;$p.TenantId=$TenantId;$p.CertificateThumbprint=$CertificateThumbprint
 } elseif ($Command.Parameters.ContainsKey('UseSystemBrowser')) {
  $p.UseSystemBrowser=$true
 } elseif ($Command.Parameters.ContainsKey('ModernAuth')) {
  # Supported interactive modern-auth prompt for versions without UseSystemBrowser.
  $p.ModernAuth=$true
 } else {
  throw 'SharePoint prerequisite: loaded Connect-SPOService exposes neither UseSystemBrowser nor ModernAuth. Update Microsoft.Online.SharePoint.PowerShell in Windows PowerShell 5.1 and restart pwsh.'
 }
 if ($Cloud -eq 'GCCHigh') {
  if (-not $Command.Parameters.ContainsKey('AuthenticationUrl')) {
   throw 'SharePoint prerequisite: loaded Connect-SPOService lacks AuthenticationUrl required for this GCC High connection. Update the SPO module and restart pwsh.'
  }
  $p.AuthenticationUrl=$Authority+'/organizations'
 }
 return $p
}
