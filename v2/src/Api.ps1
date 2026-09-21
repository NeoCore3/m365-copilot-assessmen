# Native OAuth stays within each worker; no token cache, secrets, or refresh tokens are written.
function ConvertTo-Base64Url([byte[]]$Bytes) { [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+','-').Replace('/','_') }
function New-CertificateAssertion($Certificate,[string]$Client,[string]$Audience) {
 $now=[datetimeoffset]::UtcNow.ToUnixTimeSeconds()
 $header=@{alg='PS256';typ='JWT';'x5t#S256'=(ConvertTo-Base64Url ([Security.Cryptography.SHA256]::HashData($Certificate.RawData)))}
 $claims=@{aud=$Audience;iss=$Client;sub=$Client;jti=[guid]::NewGuid().ToString();nbf=$now-30;iat=$now;exp=$now+300}
 $h=ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes(($header|ConvertTo-Json -Compress)))
 $c=ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes(($claims|ConvertTo-Json -Compress)))
 $rsa=[Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
 if(-not $rsa){throw 'Certificate needs an accessible RSA private key.'}
 try { $sig=$rsa.SignData([Text.Encoding]::UTF8.GetBytes("$h.$c"),[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pss); "$h.$c.$(ConvertTo-Base64Url $sig)" } finally {$rsa.Dispose()}
}
function Invoke-OAuthPost([string]$Uri,[hashtable]$Body) {
 try { Invoke-RestMethod -Method Post -Uri $Uri -Body $Body -ContentType 'application/x-www-form-urlencoded' -TimeoutSec 60 -MaximumRedirection 0 -ErrorAction Stop }
 catch {
  $code='request_failed'
  try {$e=$_.ErrorDetails.Message|ConvertFrom-Json;if($e.error -match '^[a-zA-Z0-9_]+$'){$code=$e.error}}catch{}
  throw "OAuth $code. Check app consent, tenant, authentication policy and certificate/public-client setup."
 }
}
function Connect-AssessmentApi([string]$Resource,[string[]]$Scopes) {
 $client=if($request.Authentication -eq 'Certificate'){$request.ClientId}else{$request.ApiClientId}
 if(-not $client){throw 'Provide ApiClientId for interactive API collection, or ClientId for certificate mode. See v2/docs/SETUP-V2.md.'}
 [void][guid]::Parse($client)
 $endpoint="https://login.microsoftonline.com/$($request.TenantId)/oauth2/v2.0"
 if($request.Authentication -eq 'Certificate'){
  $thumb=$request.CertificateThumbprint
  if($thumb -notmatch '^[A-Fa-f0-9]{40}$'){throw 'Invalid certificate thumbprint.'}
  $cert=Get-Item "Cert:\CurrentUser\My\$thumb" -ErrorAction Stop
  if(-not $cert.HasPrivateKey -or $cert.NotAfter.ToUniversalTime() -le [datetime]::UtcNow -or $cert.NotBefore.ToUniversalTime() -gt [datetime]::UtcNow){throw 'Certificate is expired, not yet valid, or lacks its private key.'}
  $token=Invoke-OAuthPost "$endpoint/token" @{client_id=$client;scope="$Resource/.default";grant_type='client_credentials';client_assertion_type='urn:ietf:params:oauth:client-assertion-type:jwt-bearer';client_assertion=(New-CertificateAssertion $cert $client "$endpoint/token")}
 }else{
  $device=Invoke-OAuthPost "$endpoint/devicecode" @{client_id=$client;scope=($Scopes -join ' ')}
  Write-Host "Sign in for $Resource at $($device.verification_uri) using code $($device.user_code). Select the requested customer tenant."
  $deadline=[datetime]::UtcNow.AddSeconds([math]::Min(900,[int]$device.expires_in));$interval=[math]::Max(5,[int]$device.interval)
  while([datetime]::UtcNow -lt $deadline){
   Start-Sleep -Seconds $interval
   try {$token=Invoke-OAuthPost "$endpoint/token" @{client_id=$client;grant_type='urn:ietf:params:oauth:grant-type:device_code';device_code=$device.device_code};break}
   catch {if($_.Exception.Message -match 'OAuth authorization_pending\.') {continue};if($_.Exception.Message -match 'OAuth slow_down\.'){ $interval+=5;continue };throw}
  }
  if(-not $token){throw 'Interactive sign-in timed out.'}
 }
 if(-not $token.access_token){throw 'Authentication returned no access token.'}
 $script:apiToken=$token.access_token;$script:apiExpiry=[datetime]::UtcNow.AddSeconds([int]$token.expires_in-60)
}
function Assert-ApiUri([string]$Uri,[string]$Origin) {
 $u=[uri]$Uri;$o=[uri]$Origin
 if(-not $u.IsAbsoluteUri -or $u.Scheme -ne 'https' -or $u.Host -ne $o.Host -or $u.Port -ne 443 -or $u.UserInfo -or $u.Fragment){throw 'Unsafe or cross-origin API continuation rejected.'}
}
function Invoke-ApiGet([string]$Uri,[string]$Origin) {
 Assert-ApiUri $Uri $Origin
 if([datetime]::UtcNow -ge $script:apiExpiry){throw 'API token expired; rerun this workload. Partial data is retained.'}
 for($attempt=0;$attempt -lt 5;$attempt++){
  try {return Invoke-RestMethod -Uri $Uri -Headers @{Authorization="Bearer $script:apiToken"} -Method Get -TimeoutSec 120 -MaximumRedirection 0 -ErrorAction Stop}
  catch {
   $status=[int]$_.Exception.Response.StatusCode
   if($status -in @(429,503) -and $attempt -lt 4){
    $delay=[int][math]::Pow(2,$attempt+1)
    try {
     $after=$_.Exception.Response.Headers.RetryAfter
     $retry=if($after.Delta){$after.Delta.TotalSeconds}elseif($after.Date){($after.Date-[datetimeoffset]::UtcNow).TotalSeconds}else{0}
     if($retry -gt 0){$delay=[math]::Ceiling($retry)}
    }catch{}
    if($delay -gt 60){throw "HTTP $status requires retry after $delay seconds; rerun later. Partial data is retained."}
    Start-Sleep -Seconds $delay;continue
   }
   throw "HTTP $status from $(([uri]$Origin).Host). Check workload permissions, licensing and service availability."
  }
 }
}
function Read-ApiPages([string]$Uri,[string]$Field='value',[int]$SkipPageSize=0) {
 $origin=([uri]$Uri).GetLeftPart([UriPartial]::Authority);$initial=$Uri;$seen=[Collections.Generic.HashSet[string]]::new();$page=0;$skip=0
 while($Uri){
  if(++$page -gt $request.MaxPages){throw 'Page limit reached.'}
  if(-not $seen.Add($Uri)){throw 'Repeated API continuation.'}
  $response=Invoke-ApiGet $Uri $origin
  if($null -eq $response.PSObject.Properties[$Field]){throw "Expected API collection field '$Field' missing."}
  $rows=@($response.$Field | Where-Object {$null -ne $_});foreach($row in $rows){Add-WorkerRow $row}
  $Uri=$response.'@odata.nextLink'
  if(-not $Uri){$Uri=$response.continuationUri}
  if(-not $Uri -and $response.continuationToken){$sep=if($initial.Contains('?')){'&'}else{'?'};$Uri=$initial+$sep+'continuationToken='+[uri]::EscapeDataString($response.continuationToken)}
  if(-not $Uri -and $SkipPageSize -gt 0 -and $rows.Count -eq $SkipPageSize){$skip+=$SkipPageSize;$Uri=$initial+'&$skip='+$skip}
 }
}
