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
 foreach ($r in $Rows) {
  $names = if ($r -is [System.Collections.IDictionary]) { $r.Keys } else { $r.PSObject.Properties.Name }
  foreach ($n in $names) { if (-not $columns.Contains([string]$n)) { $columns.Add([string]$n) } }
 }
 $safe = foreach ($r in $Rows) {
  $o = [ordered]@{}
  foreach ($n in $columns) { $o[$n] = ConvertTo-SafeCell $r.$n }
  [pscustomobject]$o
 }
 $safe | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding utf8
}
function ConvertTo-HtmlText { param($Value) [System.Net.WebUtility]::HtmlEncode([string]$Value) }
function Write-AssessmentReport {
 param($Manifest, [string]$Directory)
 $h = [System.Text.StringBuilder]::new()
 [void]$h.Append(@'
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Microsoft 365 Copilot assessment</title><style>
:root{font-family:Segoe UI,Arial,sans-serif;color:#17243b;background:#f2f5fa}body{margin:0}header{background:#102641;color:white;padding:36px 5vw}main{max-width:1380px;margin:auto;padding:24px}h1{margin:8px 0}h2{color:#124878}section,.card{background:white;border:1px solid #dce4ef;border-radius:12px;padding:22px;margin:18px 0}table{border-collapse:collapse;width:100%;font-size:13px}th,td{padding:9px;border-bottom:1px solid #dce4ef;text-align:left;vertical-align:top;overflow-wrap:anywhere}th{background:#edf3fa}a{color:#075dad}header a{color:white}.scroll{overflow:auto;max-height:480px}.meta{color:#5a677a}nav{display:flex;gap:15px;flex-wrap:wrap}.bar{height:18px;background:#197f91;border-radius:3px}.chart{display:grid;grid-template-columns:210px 1fr 70px;gap:12px;align-items:center}.note{border-left:4px solid #df982c;padding:12px;background:#fff8e9}details{margin-top:12px}input{padding:10px;width:90%;max-width:480px}footer{padding:24px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:15px}@media print{header{background:white;color:black}.scroll{max-height:none}details{display:block}nav,input{display:none}}
</style></head><body>
'@)
 [void]$h.Append("<header><p>MICROSOFT 365 • COPILOT ENABLEMENT</p><h1>$(ConvertTo-HtmlText $Manifest.CustomerName)</h1><p>$(ConvertTo-HtmlText $Manifest.Cloud) | $(ConvertTo-HtmlText $Manifest.Authentication) | Collected $(ConvertTo-HtmlText $Manifest.CollectedAtUtc)</p></header><main>")
 [void]$h.Append('<section><h2>Executive briefing</h2><p>This report records the evidence available for licensing, usage, configuration and governance. Collection success measures evidence coverage; it is not a security score or approval to expand Copilot.</p><p class="note">Missing evidence does not mean a control is disabled. Policy existence does not prove enforcement. Validate policy scope, exclusions, simulation modes and effectiveness before approving expansion.</p><p>Usage window: '+(ConvertTo-HtmlText $Manifest.Period)+'. Configuration is a point-in-time snapshot. Preserve report refresh dates and avoid combining different populations or time windows.</p><nav>')
 foreach ($w in @($Manifest.Results | Select-Object -ExpandProperty Workstream -Unique)) { [void]$h.Append("<a href='#$w'>$(ConvertTo-HtmlText $w)</a>") }
 [void]$h.Append('</nav></section><section><h2>Evidence collection coverage</h2><div class="chart">')
 foreach ($g in @($Manifest.Results | Group-Object Status)) {
  $pct = [math]::Round(100 * $g.Count / [math]::Max(1,$Manifest.Results.Count),1)
  [void]$h.Append("<span>$(ConvertTo-HtmlText $g.Name)</span><div class='bar' style='width:$pct%' role='img' aria-label='$pct percent'></div><span>$($g.Count)</span>")
 }
 [void]$h.Append('</div></section>')
 $license = $Manifest.Results | Where-Object Id -eq 'Licenses'
 if ($license.Status -eq 'Collected') {
  $licPath = Join-Path $Directory 'raw/Licenses.json'
  $lic = @(Get-Content -LiteralPath $licPath -Raw | ConvertFrom-Json)
  [void]$h.Append('<section><h2>License allocation</h2><p>Enabled subscription units and consumed units are reported per SKU. Available units are not a recommendation to buy or reclaim licenses.</p><div class="scroll"><table><tr><th>SKU</th><th>Enabled</th><th>Consumed</th><th>Available</th><th>Allocation</th></tr>')
  foreach ($l in $lic) {
   $enabled = [int]$l.prepaidUnits.enabled; $consumed = [int]$l.consumedUnits
   $pct = if ($enabled -gt 0) { [math]::Min(100,[math]::Round(100*$consumed/$enabled,1)) } else { 0 }
   [void]$h.Append("<tr><td>$(ConvertTo-HtmlText $l.skuPartNumber)</td><td>$enabled</td><td>$consumed</td><td>$($enabled-$consumed)</td><td><div class='bar' style='width:$pct%' aria-label='$pct percent'></div></td></tr>")
  }
  [void]$h.Append('</table></div></section>')
 }
 [void]$h.Append('<section><h2>Search evidence</h2><input id="filter" placeholder="Filter dataset names and explanations" aria-label="Filter evidence"></section>')
 foreach ($w in @($Manifest.Results | Select-Object -ExpandProperty Workstream -Unique)) {
  [void]$h.Append("<section id='$w'><h2>$(ConvertTo-HtmlText $w)</h2>")
  foreach ($r in @($Manifest.Results | Where-Object Workstream -eq $w)) {
   [void]$h.Append("<article class='dataset'><h3>$(ConvertTo-HtmlText $r.Id)</h3><p><strong>$(ConvertTo-HtmlText $r.Status)</strong> | Rows: $(ConvertTo-HtmlText $r.RowCount) | <a href='csv/$($r.Id).csv'>Download CSV</a></p><p>$(ConvertTo-HtmlText $r.Explanation)</p><p class='meta'>Source: $(ConvertTo-HtmlText $r.Source)</p>")
   if ($r.RowCount -gt 0) {
    $preview = @(Import-Csv -LiteralPath (Join-Path $Directory "csv/$($r.Id).csv") | Select-Object -First 100)
    if ($preview.Count -gt 0) {
     [void]$h.Append('<details><summary>Preview: first 100 rows, 20 columns, 300 characters per cell; CSV/JSON contain full collected data</summary><div class="scroll"><table><thead><tr>')
     $cols = @($preview[0].PSObject.Properties.Name | Select-Object -First 20)
     foreach ($c in $cols) { [void]$h.Append("<th>$(ConvertTo-HtmlText $c)</th>") }
     [void]$h.Append('</tr></thead><tbody>')
     foreach ($row in $preview) {
      [void]$h.Append('<tr>')
      foreach ($c in $cols) { [void]$h.Append("<td>$(ConvertTo-HtmlText (([string]$row.$c).Substring(0,[math]::Min(300,([string]$row.$c).Length))))</td>") }
      [void]$h.Append('</tr>')
     }
     [void]$h.Append('</tbody></table></div></details>')
    }
   }
   [void]$h.Append('</article>')
  }
  [void]$h.Append('</section>')
 }
 [void]$h.Append(@'
<section><h2>Expansion decision gates</h2><table><tr><th>Gate</th><th>Evidence required before approval</th></tr>
<tr><td>License optimization</td><td>Reconcile assigned SKUs, disabled plans and usage identities; validate inactivity with managers before reclamation. Review unlicensed Chat demand separately.</td></tr>
<tr><td>Data access</td><td>Review EEEU, anonymous links, broken inheritance and OneDrive exposure. Establish baselines and verify reduction on priority sites; validate restricted access controls.</td></tr>
<tr><td>Protection</td><td>Validate DLP enforcement with controlled tests, approve auto-labeling simulation results, verify retention and legal hold requirements with owners.</td></tr>
<tr><td>Agents</td><td>Review owners, permissions, connectors, authentication, data sources, publication scope and lifecycle. Establish an operating review process.</td></tr>
<tr><td>Governance</td><td>Approve acceptable use, appoint control owners and a governance board, record KPI baselines and approve each expansion cohort.</td></tr></table></section>
</main><footer>Confidential assessment output • Generated locally • Review collection-status.csv before using findings.</footer>
<script>document.getElementById('filter').addEventListener('input',function(){let q=this.value.toLowerCase();document.querySelectorAll('.dataset').forEach(e=>e.hidden=!e.textContent.toLowerCase().includes(q));});</script></body></html>
'@)
 $h.ToString() | Set-Content -LiteralPath (Join-Path $Directory 'Assessment.html') -Encoding utf8
}
