# The SPO module constructs the filename from the label name. A backslash in
# that name can become a missing child directory. Retry only a contained path;
# never rename tenant labels, trust a traversal path, or mask a service error.
function Export-AssessmentDagReport {
 param([string]$ReportId,[string]$Folder)
 try { Export-SPODataAccessGovernanceInsight -ReportID $ReportId -DownloadPath $Folder -ErrorAction Stop|Out-Null }
 catch {
  $original=$_
  $match=[regex]::Match($_.Exception.Message,"Could not find a part of the path '([^']+)'",'IgnoreCase')
  if(-not $match.Success){throw}
  $candidate=$match.Groups[1].Value
  if(-not [IO.Path]::IsPathFullyQualified($candidate) -or $candidate -match '(^|[\\/])\.\.([\\/]|$)'){throw}
  $base=[IO.Path]::GetFullPath($Folder).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
  $full=[IO.Path]::GetFullPath($candidate)
  $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
  if(-not $full.StartsWith($base,$comparison) -or [IO.Path]::GetExtension($full) -ne '.csv'){throw}
  $parent=[IO.Path]::GetDirectoryName($full)
  if($parent -eq $base.TrimEnd([IO.Path]::DirectorySeparatorChar)){throw}
  # Do not follow pre-existing junctions/symlinks out of the download tree.
  $probe=$parent
  while($probe){
   if(Test-Path -LiteralPath $probe){
    if((Get-Item -LiteralPath $probe -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw $original}
   }
   $next=[IO.Path]::GetDirectoryName($probe);if($next -eq $probe){break};$probe=$next
  }
  New-Item -ItemType Directory -Path $parent -Force|Out-Null
  Write-Host "Retrying DAG export $ReportId after preparing its contained filename directory."
  Export-SPODataAccessGovernanceInsight -ReportID $ReportId -DownloadPath $Folder -ErrorAction Stop|Out-Null
 }
}
