function ConvertTo-SafeCell {
 param($Value)
 if ($null -eq $Value) { return '' }
 if ($Value -isnot [string] -and $Value -is [System.Collections.IEnumerable]) {
  $Value = ConvertTo-Json -InputObject $Value -Depth 30 -Compress
 } elseif ($Value -is [System.Management.Automation.PSCustomObject] -or $Value -is [System.Collections.IDictionary]) {
  $Value = ConvertTo-Json -InputObject $Value -Depth 30 -Compress
 }
 $s = [string]$Value
 # Protect spreadsheet applications when CSV files are opened by a reviewer.
 if ($s -match '^\s*[=+\-@]' -or $s -match '^[\t\r\n]') { return "'" + $s }
 return $s
}
function Export-SafeCsv {
 param([object[]]$Rows, [string]$Path)
 if (@($Rows).Count -eq 0) { '"CollectionStatus","Explanation"' | Set-Content -LiteralPath $Path -Encoding utf8; return }
 $columns = [System.Collections.Generic.List[string]]::new()
 $seenColumns = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 foreach ($r in $Rows) {
  $names = if ($r -is [System.Collections.IDictionary]) { $r.Keys } else { $r.PSObject.Properties.Name }
  foreach ($n in $names) { if ($seenColumns.Add([string]$n)) { $columns.Add([string]$n) } }
 }
 $safe = foreach ($r in $Rows) {
  $o = [ordered]@{}
  foreach ($n in $columns) { $o[$n] = ConvertTo-SafeCell $r.$n }
  [pscustomobject]$o
 }
 $safe | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding utf8
}
function ConvertTo-HtmlText { param($Value) [System.Net.WebUtility]::HtmlEncode([string]$Value) }
# Dashboard and reviewer exports keep raw JSON and original CSV evidence intact.
. (Join-Path $PSScriptRoot 'ReviewExports.ps1')
. (Join-Path $PSScriptRoot 'Remediation.ps1')
. (Join-Path $PSScriptRoot 'Dashboard.ps1')
