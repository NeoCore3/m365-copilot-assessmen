. (Join-Path $PSScriptRoot 'Diagnostics.ps1')
function Add-WorkerRow($Row) {
 if($workerRows.Count -ge $request.MaxRows){throw 'Row limit reached.'}
 if($null -ne $Row){$workerRows.Add($Row)}
}
function Invoke-WorkerDataset($Definition,[scriptblock]$Read) {
 $workerRows.Clear();$state='Collected';$note=$Definition.Explanation;$script:datasetStatus=$null;$script:datasetNote=$null
 $script:datasetScope=[ordered]@{RequestedPeriod=$request.Period;MaxPages=$request.MaxPages;MaxRows=$request.MaxRows;MaxItems=$request.MaxItems;EnvironmentUrl=$Definition.EnvironmentUrl;DriveIds=$request.DriveIds}
 try { & $Read | Out-Null; if($script:datasetStatus){$state=$script:datasetStatus};if($script:datasetNote){$note+=' '+$script:datasetNote} }
 catch {
  $state=if($workerRows.Count -or $_.Exception.Message -match 'limit reached|cap reached|limited to the last 30 days'){'Incomplete'}elseif($_.Exception -is [Management.Automation.CommandNotFoundException]){'CommandUnavailable'}else{'Failed'}
  # Do not serialize error records, OAuth responses, headers, or command invocation arguments.
  $message=Protect-AssessmentDiagnostic $_.Exception.Message
  if($message.Length -gt 1200){$message=$message.Substring(0,1200)}
  $note+=' '+$message
 }
 $workerResults.Add([pscustomobject]@{Id=$Definition.Id;Workstream=$Definition.Workstream;Source=$Definition.Source;Status=$state;Explanation=$note;Scope=$script:datasetScope;Rows=$workerRows.ToArray()})
}
