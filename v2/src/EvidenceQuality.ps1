# Preserve typed JSON dates. Parsing a DateTime as a string discards its Kind and
# reinterprets UTC clock time in the workstation's local zone.
function ConvertTo-AssessmentUtc($Value) {
 if($Value -is [datetimeoffset]){return $Value.UtcDateTime}
 if($Value -is [datetime]){
  if($Value.Kind -eq [DateTimeKind]::Unspecified){throw 'UTC request timestamp has no time-zone information.'}
  return $Value.ToUniversalTime()
 }
 $s=[string]$Value
 if($s -notmatch '(Z|[+-]\d{2}:\d{2})$'){throw 'UTC request timestamp must contain Z or an explicit offset.'}
 return [datetimeoffset]::Parse($s,[Globalization.CultureInfo]::InvariantCulture).UtcDateTime
}
function Get-AssessmentTeamsParameters($Command,$Request) {
 $p=@{TenantId=$Request.TenantId;ErrorAction='Stop'}
 if($Request.Authentication -eq 'Certificate'){$p.ApplicationId=$Request.ClientId;$p.CertificateThumbprint=$Request.CertificateThumbprint;return $p}
 if($Request.DisableWAM){
  if($Command.Parameters.ContainsKey('DisableWAM')){$p.DisableWAM=$true}
  elseif($Command.Module.Version -and $Command.Module.Version -lt [version]'7.8.1'){
   Write-Warning 'This Teams module predates WAM integration; using its existing interactive sign-in. Exchange DisableWAM remains enabled.'
  }elseif($Command.Parameters.ContainsKey('UseDeviceAuthentication')){
   Write-Warning 'Teams lacks DisableWAM; using supported device-code sign-in. Customer authentication policies still apply.'
   $p.UseDeviceAuthentication=$true
  }else{throw 'Teams module cannot provide the requested authentication method. Update MicrosoftTeams.'}
 }
 return $p
}
function Get-ReportIdentityQuality([string]$Id,[object[]]$Rows) {
 $fields=@('User Principal Name','Owner Principal Name','Site URL')
 foreach($field in $fields){
  if(-not $Rows.Count -or $null -eq $Rows[0].PSObject.Properties[$field]){continue}
  $values=@($Rows|ForEach-Object {[string]$_.$field})
  $missing=@($values|Where-Object {[string]::IsNullOrWhiteSpace($_)}).Count
  $concealed=@($values|Where-Object {$_ -match '^[A-Fa-f0-9]{32}$'}).Count
  [pscustomobject]@{Dataset=$Id;Field=$field;Rows=$Rows.Count;Blank=$missing;ConcealedFormat=$concealed;Finding=$(if($concealed){'Concealed identifiers observed'}elseif($missing -eq $Rows.Count){'All values blank'}else{'Values present; review any blanks'});Action='Confirm Microsoft 365 admin center > Settings > Org settings > Services > Reports. Concealed usage identifiers cannot be joined reliably to directory users. This collector does not change that tenant setting.'}
 }
}
function ConvertTo-ActivityMetadata($Row) {
 # Documented export fields, rather than invented CreationTime/Id projections.
 # Exclude free-form Subject, Justification, EntityProperties and content fields.
 $allowed=@('RecordIdentity','Happened','Activity','Workload','User','UserType','UserSku','Application','FullUrl','FilePath','PolicyId','PolicyName','PolicyMode','DlpPolicyMatchId','RuleId','RuleName','RuleActions','EnforcementMode','SensitivityLabel','SensitivityLabelPolicyId','RetentionLabel','IsProtected','CopilotAppHost','CopilotType')
 $o=[ordered]@{}
 foreach($name in $allowed){if($null -ne $Row.PSObject.Properties[$name]){$o[$name]=$Row.$name}}
 $o.SourceFields=@($Row.PSObject.Properties.Name)
 [pscustomobject]$o
}
