function Read-AgentCatalog {
 $next='https://graph.microsoft.com/v1.0/copilot/admin/catalog/packages'
 $pages=0;$seen=[Collections.Generic.HashSet[string]]::new();$ids=[Collections.Generic.HashSet[string]]::new();$failed=$false
 while($next){
  if(++$pages -gt $request.MaxPages){throw 'Agent catalog page limit reached.'}
  Assert-ApiUri $next 'https://graph.microsoft.com'
  if(-not $seen.Add($next)){throw 'Agent catalog repeated a continuation URL.'}
  $page=Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject -ErrorAction Stop
  if($null -eq $page.PSObject.Properties['value']){throw 'Agent catalog response is missing value.'}
  foreach($package in $page.value){
   if(-not $package.id){throw 'Agent catalog package has no ID.'}
   if(-not $ids.Add([string]$package.id)){continue}
   if($workerRows.Count -ge $request.MaxItems){throw 'Agent catalog item limit reached; increase MaxItems for the approved scope.'}
   if(Get-Command Set-WorkerProgress -ErrorAction SilentlyContinue){Set-WorkerProgress "Agent catalog: page $pages, package $($workerRows.Count+1)"}
   $detail=$null;$errorText='';$state='Collected'
   try{
    $uri='https://graph.microsoft.com/v1.0/copilot/admin/catalog/packages/'+[uri]::EscapeDataString([string]$package.id)
    $detail=Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject -ErrorAction Stop
    if(-not $detail.id -or $detail.id -ne $package.id){throw 'Package detail response ID is missing or mismatched.'}
   }catch{$state='Failed';$failed=$true;$errorText=Protect-AssessmentDiagnostic $_.Exception.Message}
   Add-WorkerRow ([pscustomobject]@{Id=$package.id;DisplayName=$package.displayName;DetailStatus=$state;DetailError=$errorText;Package=$package;Details=$detail})
  }
  $next=$page.'@odata.nextLink'
 }
 if($failed){throw 'Some agent catalog detail requests failed. Inventory rows are retained; inspect DetailStatus and DetailError.'}
}
