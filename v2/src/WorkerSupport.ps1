function Add-WorkerRow($Row) {
 if($workerRows.Count -ge $request.MaxRows){throw 'Row limit reached.'}
 if($null -ne $Row){$workerRows.Add($Row)}
}
function Invoke-WorkerDataset($Definition,[scriptblock]$Read) {
 $workerRows.Clear();$state='Collected';$note=$Definition.Explanation
 try { & $Read | Out-Null }
 catch {
  $state=if($workerRows.Count -or $_.Exception.Message -match 'limit reached|cap reached|limited to the last 30 days'){'Incomplete'}elseif($_.Exception -is [Management.Automation.CommandNotFoundException]){'CommandUnavailable'}else{'Failed'}
  # Do not serialize error records, OAuth responses, headers, or command invocation arguments.
  $message=$_.Exception.Message -replace '(?i)(Bearer\s+)[^\s]+','$1[redacted]'
  $message=$message -replace 'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+','[redacted token]'
  if($message.Length -gt 1200){$message=$message.Substring(0,1200)}
  $note+=' '+$message
 }
 $workerResults.Add([pscustomobject]@{Id=$Definition.Id;Workstream=$Definition.Workstream;Source=$Definition.Source;Status=$state;Explanation=$note;Rows=$workerRows.ToArray()})
}
