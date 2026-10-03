function ConvertTo-ReviewValue {
 param($Value,[int]$Depth=0)
 if($null -eq $Value){return ''}
 if($Value -is [datetime]){return $Value.ToString('o')}
 if($Value -is [bool]){return $(if($Value){'Yes'}else{'No'})}
 if($Depth -gt 12){return (ConvertTo-Json -InputObject $Value -Depth 50 -Compress)}
 if($Value -is [string]){
  $s=$Value.Trim()
  if($s.StartsWith('{') -or $s.StartsWith('[')){
   try {$obj=ConvertFrom-Json -InputObject $s -AsHashtable -ErrorAction Stop;return (ConvertTo-ReviewValue $obj ($Depth+1))}catch{}
  }
  if($script:reviewLookup -and $script:reviewLookup.ContainsKey($Value)){return "$($script:reviewLookup[$Value]) [$Value]"}
  return $Value
 }
 if($Value -is [Collections.IDictionary] -or $Value -is [Management.Automation.PSCustomObject]){
  $names=if($Value -is [Collections.IDictionary]){@($Value.Keys)}else{@($Value.PSObject.Properties.Name)}
  return (($names|ForEach-Object {"$($_): $(ConvertTo-ReviewValue $Value.$_ ($Depth+1))"}) -join '; ')
 }
 if($Value -is [Collections.IEnumerable]){return ((@($Value)|ForEach-Object {ConvertTo-ReviewValue $_ ($Depth+1)}) -join "`n")}
 return [string]$Value
}
function Add-ReviewFields {
 param($Value,[string]$Prefix,[Collections.IDictionary]$Output,[int]$Depth=0)
 if(($Value -is [Collections.IDictionary] -or $Value -is [Management.Automation.PSCustomObject]) -and $Depth -lt 6){
  $names=if($Value -is [Collections.IDictionary]){@($Value.Keys)}else{@($Value.PSObject.Properties.Name)}
  if(-not $names.Count -and $Prefix){$Output[$Prefix]=''}
  foreach($n in $names){
   if($n -in @('PSComputerName','RunspaceId','PSShowComputerName','PSObject')){continue}
   $key=if($Prefix){"$Prefix.$n"}else{[string]$n}
   Add-ReviewFields $Value.$n $key $Output ($Depth+1)
  }
 }else{
  $key=$Prefix;$suffix=1;while($Output.Contains($key)){$suffix++;$key="$Prefix [field $suffix]"}
  $Output[$key]=ConvertTo-ReviewValue $Value
 }
}
function Export-AssessmentReview {
 param($Manifest,[string]$Directory)
 $review=Join-Path $Directory 'readable';New-Item -ItemType Directory $review -Force|Out-Null
 $script:reviewLookup=@{}
 foreach($spec in @(@('UserAssignments','id','userPrincipalName'),@('SensitivityLabels','ImmutableId','DisplayName'),@('Licenses','skuId','skuPartNumber'))){
  $p=Join-Path $Directory "raw/$($spec[0]).json"
  if(Test-Path -LiteralPath $p){foreach($r in @(Get-Content -LiteralPath $p -Raw|ConvertFrom-Json -Depth 100 -AsHashtable)){if($r.($spec[1]) -and $r.($spec[2])){$script:reviewLookup[[string]$r.($spec[1])]=[string]$r.($spec[2])}}}
 }
 $dictionary=[Collections.Generic.List[object]]::new()
 foreach($r in $Manifest.Results){
  if(Get-Command Update-AssessmentProgress -ErrorAction SilentlyContinue){Update-AssessmentProgress "Formatting readable export: $($r.Id)"}
  if($r.Id -notmatch '^[A-Za-z0-9_-]+$'){throw 'Unsafe dataset identifier in manifest.'}
  $raw=Join-Path $Directory "raw/$($r.Id).json"
  $source=if((Test-Path -LiteralPath $raw) -and $r.Status -in @('Collected','Incomplete','Derived','Imported')){@(Get-Content -LiteralPath $raw -Raw|ConvertFrom-Json -Depth 100 -AsHashtable)}else{@()}
  $rows=@(foreach($record in $source){
   $o=[ordered]@{};Add-ReviewFields $record '' $o
   $priority=@('displayName','DisplayName','Name','name','Title','userPrincipalName','UserPrincipalName','UserId','Url','Owner','EnvironmentName','ReportId','ServiceStatus','ExportStatus','Mode','State','Status','Enabled','Disabled')
   $ordered=[ordered]@{};foreach($k in $priority){if($o.Contains($k) -and -not $ordered.Contains($k)){$ordered[$k]=$o[$k]}}
   foreach($k in $o.Keys){if(-not $ordered.Contains($k)){$ordered[$k]=$o[$k]}}
   [pscustomobject]$ordered
  })
  if(-not $rows.Count){$rows=@([pscustomobject]@{CollectionStatus=$r.Status;RecordsReturned=$r.RowCount;Explanation=$r.Explanation})}
  Export-SafeCsv $rows (Join-Path $review "$($r.Id).csv")
  $fields=@($rows|ForEach-Object {$_.PSObject.Properties.Name}|Select-Object -Unique)
  foreach($field in $fields){$dictionary.Add([pscustomobject]@{Dataset=$r.Id;Column=$field;Meaning='Source property path; dot separates nested object fields. Arrays use line-separated values. Yes/No represents Boolean only. Resolved IDs retain [original ID]. Case-colliding field names receive a [field N] suffix.';Source=$r.Source;RawEvidence="raw/$($r.Id).json"})}
 }
 Export-SafeCsv $dictionary.ToArray() (Join-Path $review 'Field-guide.csv')
 foreach($g in @($Manifest.Results|Group-Object Workstream)){
  # A long-form table avoids thousands of mostly empty columns across unrelated schemas.
  $combined=foreach($r in $g.Group){
   $recordNumber=0
   foreach($row in @(Import-Csv -LiteralPath (Join-Path $review "$($r.Id).csv"))){
    $recordNumber++
    foreach($p in $row.PSObject.Properties){
     [pscustomobject]@{EvidenceDataset=$r.Id;EvidenceStatus=$r.Status;RecordNumber=$recordNumber;Field=$p.Name;Value=$p.Value;EvidenceSource=$r.Source;EvidenceCollectedAtUtc=$r.CollectedAtUtc}
    }
   }
  }
  Export-SafeCsv @($combined) (Join-Path $review "Workstream-$($g.Name).csv")

 }
 @'
Start with Assessment.html. The readable folder contains reviewer-friendly CSVs.
raw/*.json and csv/*.csv retain the original collected evidence. They are not replaced.
Nested objects become dotted columns (for example prepaidUnits.enabled). Arrays become line-separated text, and nested array objects use named key/value pairs. Deep objects remain text. No numerical enum is guessed.
Known user, label and SKU IDs are resolved only using this run's collected evidence; the original ID remains in brackets. Blank values mean the source did not provide a value, not that a control is disabled. A Boolean No is not automatically a security failure.
Field-guide.csv maps each reviewer column to its source. Each Workstream CSV uses Dataset, RecordNumber, Field and Value columns with provenance. Filter by dataset/record to inspect each setting without a JSON wrapper.
Raw JSON remains the authoritative source for types, complex rules, array boundaries and complete policy interpretation.
'@ | Set-Content (Join-Path $review 'README.txt') -Encoding utf8
}
