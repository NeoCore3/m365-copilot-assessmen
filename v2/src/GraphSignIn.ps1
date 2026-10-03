function Write-AssessmentAuthMessage {
 param([string]$Message)
 # Write directly to the console and flush before the SDK waits for sign-in.
 [Console]::WriteLine($Message)
 [Console]::Out.Flush()
}
function Connect-AssessmentGraphSession {
 param([hashtable]$Parameters)
 $oldProgress=$ProgressPreference
 try {
  Write-Progress -Id 1 -Activity 'M365 assessment' -Completed
  $ProgressPreference='SilentlyContinue'
  if($Parameters.UseDeviceCode){
   Write-AssessmentAuthMessage 'GRAPH DEVICE-CODE SIGN-IN: no popup opens. Wait for the Microsoft URL and code below, then complete sign-in in your browser.'
  }elseif(-not $Parameters.CertificateThumbprint){
   Write-AssessmentAuthMessage 'GRAPH BROWSER SIGN-IN: complete the browser/account-picker prompt. Check behind other windows. Press Esc if the console title starts with Select.'
  }
  Connect-MgGraph @Parameters | ForEach-Object { Write-AssessmentAuthMessage ([string]$_) }
  Write-AssessmentAuthMessage 'Graph authentication command completed; verifying tenant context.'
 }finally{$ProgressPreference=$oldProgress}
}
