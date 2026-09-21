function Get-GraphRows {
 param([string]$Path,[switch]$Csv)
 $url = $profile.GraphRoot + $Path
 $rows = [System.Collections.Generic.List[object]]::new()
 $visited = [System.Collections.Generic.HashSet[string]]::new()
 do {
  $u=[uri]$url
  if ($u.Scheme -ne 'https' -or $u.Host -ne ([uri]$profile.GraphRoot).Host) { throw 'Refusing a nextLink outside the selected Graph cloud.' }
  if (-not $visited.Add($url)) { throw 'Repeated Graph nextLink detected.' }
  # SDK handles transient retry responses. A terminal error marks the entire dataset failed.
  if ($Csv) {
   $temp = Join-Path $directory ('raw/' + [guid]::NewGuid().ToString('N') + '.tmp')
   try {
    Invoke-MgGraphRequest -Method GET -Uri $url -OutputFilePath $temp | Out-Null
    $body=Get-Content -LiteralPath $temp -Raw
    if ([string]::IsNullOrWhiteSpace($body)) { return @() }
    if ($body.TrimStart().StartsWith('{')) {
     $json=$body | ConvertFrom-Json
     if ($null -eq $json.value) { throw 'Unexpected JSON usage report response.' }
     foreach ($r in @($json.value)) { $rows.Add($r) }
     $url=$json.'@odata.nextLink'
    } elseif ($body.TrimStart().StartsWith('<')) { throw 'Unexpected HTML report response.' }
    else {
     $parsed=@($body | ConvertFrom-Csv)
     if ($parsed.Count -gt 0 -and @($parsed[0].PSObject.Properties).Count -lt 2) { throw 'Unexpected CSV schema.' }
     foreach($r in $parsed){$rows.Add($r)}
     $url=$null
    }
   } finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
  } else {
   $page=Invoke-MgGraphRequest -Method GET -Uri $url -OutputType PSObject
   if ($null -ne $page.PSObject.Properties['value']) {
    foreach ($r in @($page.value)) { $rows.Add($r) }
   } else { $rows.Add($page) }
   $url=$page.'@odata.nextLink'
  }
 } while ($url)
 return $rows.ToArray()
}
