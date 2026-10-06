# Render existing downloaded CSVs. This does not recollect tenant data or infer
# unique-site totals across different reports, filters, or dates.
function Get-AssessmentDagArtifacts {
 param([string]$Directory,[string]$RawPath)
 foreach($report in @(Get-Content -LiteralPath $RawPath -Raw|ConvertFrom-Json)){
  foreach($file in $report.Files){
   $rel=([string]$file.Path).Replace('\','/')
   if(-not $rel -or $rel -match '(^/|:|(^|/)\.\.(/|$))'){continue}
   $local=Join-Path $Directory ('downloads/'+$rel)
   if(-not (Test-Path -LiteralPath $local -PathType Leaf)){continue}
   $preview=[Collections.Generic.List[object]]::new();$columns=@();$count=$null;$errorText=''
   if([IO.Path]::GetExtension($local) -eq '.csv'){
    try{
     $counter=@{Value=0}
     Import-Csv -LiteralPath $local -ErrorAction Stop|ForEach-Object {
      $counter.Value++
      if($preview.Count -lt 50){$preview.Add($_)}
     }
     $count=$counter.Value
     if($preview.Count){$columns=@($preview[0].PSObject.Properties.Name|Select-Object -First 20)}
    }catch{$errorText='Could not parse downloaded CSV for preview. Open the original artifact.'}
   }
   $rows=@(foreach($row in $preview){$v=[ordered]@{};foreach($c in $columns){$s=[string]$row.$c;$v[$c]=if($s.Length -gt 2000){$s.Substring(0,2000)+' [preview shortened]'}else{$s}};$v})
   [ordered]@{label=[IO.Path]::GetFileName($rel);path=('downloads/'+(($rel.Split('/')|ForEach-Object {[uri]::EscapeDataString($_)}) -join '/'));relativePath=('downloads/'+$rel);reportId=$report.ReportId;serviceStatus=$report.ServiceStatus;exportStatus=$report.ExportStatus;reportType=$report.ReportMetadata.ReportType;created=$report.ReportMetadata.CreatedDateTime;start=$report.ReportMetadata.ReportStartTime;end=$report.ReportMetadata.ReportEndTime;rowCount=$count;columns=$columns;rows=$rows;previewError=$errorText}
  }
 }
}
