#requires -Version 7.4
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/Report.ps1')
. (Join-Path $root 'src/Runtime.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('assessment-report-test-'+[guid]::NewGuid())
foreach($d in @($temp,(Join-Path $temp 'raw'),(Join-Path $temp 'csv'))){New-Item -ItemType Directory $d|Out-Null}
try{
 $rows=@([pscustomobject]@{Name='</script><img src=x onerror=alert(1)>';Settings=[pscustomobject]@{Enabled=$false;Scopes=@('Alpha','Beta')};Formula='=HYPERLINK("https://invalid")';Owner='unknown-id'})
 ConvertTo-Json -InputObject $rows -Depth 10|Set-Content (Join-Path $temp 'raw/Example.json')
 '[{"value":1,"Value":2}]'|Set-Content (Join-Path $temp 'raw/CaseFields.json')
 $results=@([pscustomobject]@{Id='Example';Workstream='Purview';Status='Collected';RowCount=1;Source='Synthetic';Explanation='Test'},[pscustomobject]@{Id='UserAssignments';Workstream='Licensing';Status='BlockedByConnection';RowCount=0;Source='Synthetic';Explanation='Unavailable'},[pscustomobject]@{Id='SharePointSites';Workstream='SharePoint';Status='Collected';RowCount=0;Source='Synthetic';Explanation='Actual zero'},[pscustomobject]@{Id='CaseFields';Workstream='Purview';Status='Collected';RowCount=1;Source='Synthetic';Explanation='Case-sensitive source'})
 '[]'|Set-Content (Join-Path $temp 'raw/SharePointSites.json')
 $m=[pscustomobject]@{Results=$results;CustomerName='Synthetic';TenantId='00000000-0000-0000-0000-000000000001';Cloud='Commercial';Authentication='Interactive';Period='D90';ToolkitVersion='2.0.0-preview.3'}
 $hash=(Get-FileHash (Join-Path $temp 'raw/Example.json')).Hash
 Export-AssessmentReview $m $temp;Write-AssessmentReport $m $temp
 $r=Import-Csv (Join-Path $temp 'readable/Example.csv')
 if($r.'Settings.Enabled' -ne 'No' -or $r.'Settings.Scopes' -ne "Alpha`nBeta"){throw 'Nested fields/list rendering lost meaning.'}
 if(-not $r.Formula.StartsWith("'=")){throw 'CSV formula injection not escaped.'}
 if($r.Owner -ne 'unknown-id'){throw 'Unresolved identity guessed.'}
 $case=Import-Csv (Join-Path $temp 'readable/CaseFields.csv')
 if(@($case.PSObject.Properties).Count -ne 2 -or $case.'Value [field 2]' -ne '2'){throw 'Case-colliding source fields lost.'}
 if((Get-FileHash (Join-Path $temp 'raw/Example.json')).Hash -ne $hash){throw 'Raw evidence modified.'}
 $combined=Import-Csv (Join-Path $temp 'readable/Workstream-Purview.csv')
 if('Data' -in $combined[0].PSObject.Properties.Name -or 'Value' -notin $combined[0].PSObject.Properties.Name){throw 'Workstream export still contains opaque Data wrapper.'}
 $html=Get-Content (Join-Path $temp 'Assessment.html') -Raw
 if($html.Contains('</script><img')){throw 'HTML payload escaped its data container.'}
 $json=[regex]::Match($html,'(?s)<script id="assessment-data" type="application/json">(.*?)</script>').Groups[1].Value|ConvertFrom-Json
 if($null -ne ($json.metrics|Where-Object id -eq 'UserAssignments').value){throw 'Missing data displayed as zero.'}
 if(($json.metrics|Where-Object id -eq 'SharePointSites').value -ne 0){throw 'Collected zero hidden.'}
 Initialize-AssessmentProgress @('One','Two') $temp $temp 'synthetic'
 Set-AssessmentStage 'One';Update-AssessmentProgress 'Waiting for synthetic response' .5
 $progress=Get-Content (Join-Path $temp 'progress.json') -Raw|ConvertFrom-Json
 if($progress.Percent -ne 25 -or $progress.ETA -notlike 'Unknown*'){throw 'Progress fabricated a first-run ETA.'}
 Set-AssessmentStage 'Two';Complete-AssessmentProgress
 Write-Host 'Report experience tests passed: raw preservation, nested exports, field collisions, formula/HTML safety, missing-versus-zero metrics, and honest progress.'
}finally{Remove-Item $temp -Recurse -Force}
