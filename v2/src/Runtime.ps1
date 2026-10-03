. (Join-Path $PSScriptRoot 'GraphSignIn.ps1')
function Import-AssessmentGraph {
 param([string]$Version)
 $p=@{Name='Microsoft.Graph.Authentication';ErrorAction='Stop'}
 if($Version){$p.RequiredVersion=$Version}
 try {Import-Module @p}
 catch {throw "Graph module could not load. Requested version: $Version. Use a fresh process and install that version under the same Windows user. Original error: $($_.Exception.Message)"}
 Write-Host "Graph authentication module: $((Get-Module Microsoft.Graph.Authentication).Version)"
}
function Show-AssessmentSignIn {
 param([string]$Service,[string]$Purpose,[string]$Mode,[string]$Tenant,[string]$Account)
 Write-Host "`n=== AUTHENTICATION: $Service ===" -ForegroundColor Cyan
 Write-Host "Purpose: $Purpose | Tenant: $Tenant | Mode: $Mode"
 if($Mode -eq 'Interactive'){Write-Host "Account: $Account. Complete any browser/MFA prompt for this service. Other services may require separate sign-in because they use separate modules and isolated sessions."}
}
function Initialize-AssessmentProgress {
 param([string[]]$Stages,[string]$Directory,[string]$OutputRoot,[string]$Signature)
 $script:assessmentProgress=[ordered]@{Stages=$Stages;Index=-1;Current='Preparing';Started=[datetime]::UtcNow;StageStarted=[datetime]::UtcNow;Directory=$Directory;History=@{};Timings=[Collections.Generic.List[object]]::new();LastText='';LastPercent=0;Signature=$Signature}
 # Estimate only from a completed matching run. First-run ETA stays unknown.
 foreach($file in @(Get-ChildItem -LiteralPath $OutputRoot -Filter manifest.json -Recurse -ErrorAction SilentlyContinue|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 20)){
  try{$m=Get-Content $file.FullName -Raw|ConvertFrom-Json;if($m.ProgressSignature -eq $Signature -and $m.RunCompleted -and $m.StageTimings){foreach($s in $m.StageTimings){$script:assessmentProgress.History[$s.Stage]=[double]$s.Seconds};break}}catch{}
 }
 Write-Host ('Collection stages: '+($Stages -join ' -> '))
 Write-Host 'Progress measures completed stages, not data completeness. ETA uses the previous matching run, including sign-in time; otherwise it is unknown.'
}
function Set-AssessmentStage {
 param([string]$Name)
 if(-not $script:assessmentProgress){return}
 $p=$script:assessmentProgress
 if($p.Index -ge 0){$p.Timings.Add([pscustomobject]@{Stage=$p.Current;Seconds=[math]::Round(([datetime]::UtcNow-$p.StageStarted).TotalSeconds,2)})}
 $p.Index++;$p.Current=$Name;$p.StageStarted=[datetime]::UtcNow
 Update-AssessmentProgress "Starting $Name" 0
}
function Update-AssessmentProgress {
 param([string]$Detail,[double]$Fraction=0)
 if(-not $script:assessmentProgress){return}
 $p=$script:assessmentProgress;$now=[datetime]::UtcNow
 $pct=[math]::Min(99,[math]::Max(0,[math]::Floor(100*($p.Index+[math]::Min(.99,$Fraction)) / [math]::Max(1,$p.Stages.Count))))
 $pct=[math]::Max($p.LastPercent,$pct);$p.LastPercent=$pct
 $elapsed=$now-$p.Started;$eta='Unknown (no matching completed run)'
 if($p.History.Count){
  $remaining=0;$known=$true
  foreach($s in @($p.Stages|Select-Object -Skip $p.Index)){if(-not $p.History.ContainsKey($s)){$known=$false;break};$remaining+=$p.History[$s]}
  $stageElapsed=($now-$p.StageStarted).TotalSeconds
  if($known -and $stageElapsed -lt $p.History[$p.Current]){$eta='Approx. '+[math]::Ceiling([math]::Max(0,$remaining-$stageElapsed)/60)+' min (previous matching run)'}else{$eta='Unknown (stage exceeded history or history missing)'}
 }
 $status="$pct% | Stage $($p.Index+1)/$($p.Stages.Count): $($p.Current) | Elapsed $($elapsed.ToString('hh\:mm\:ss')) | ETA $eta"
 Write-Progress -Id 1 -Activity 'M365 assessment' -Status $status -CurrentOperation $Detail -PercentComplete $pct
 if($Detail -ne $p.LastText){Write-Host "[$($now.ToString('HH:mm:ss')) UTC] $status | $Detail";$p.LastText=$Detail}
 [pscustomobject]@{TimestampUtc=$now.ToString('o');Stage=$p.Current;Detail=$Detail;Percent=$pct;ElapsedSeconds=[math]::Round($elapsed.TotalSeconds);ETA=$eta}|ConvertTo-Json|Set-Content (Join-Path $p.Directory 'progress.json') -Encoding utf8
}
function Complete-AssessmentProgress {
 if(-not $script:assessmentProgress){return}
 $p=$script:assessmentProgress;$p.Timings.Add([pscustomobject]@{Stage=$p.Current;Seconds=[math]::Round(([datetime]::UtcNow-$p.StageStarted).TotalSeconds,2)})
 [pscustomobject]@{TimestampUtc=[datetime]::UtcNow.ToString('o');Stage='Completed';Detail='Report written; review evidence statuses';Percent=100;ElapsedSeconds=[math]::Round(([datetime]::UtcNow-$p.Started).TotalSeconds);ETA='0 min'}|ConvertTo-Json|Set-Content (Join-Path $p.Directory 'progress.json') -Encoding utf8
 Write-Progress -Id 1 -Activity 'M365 assessment' -Completed
 Write-Host '100% | Report generation complete. Review statuses for missing or incomplete evidence.'
}
function Set-WorkerProgress {
 param([string]$Detail,[string]$Phase='Collecting')
 if($request.ProgressPath){[pscustomobject]@{Detail=$Detail;Phase=$Phase;Completed=$workerResults.Count;Total=@($request.Definitions).Count;AtUtc=[datetime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath $request.ProgressPath -Encoding utf8}
}
function Invoke-AssessmentWorkerProcess {
 param([string]$RequestPath,[string]$ProgressPath)
 $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'});$info.UseShellExecute=$false
 foreach($arg in @('-NoProfile','-File',(Join-Path $PSScriptRoot 'Worker.ps1'),'-RequestPath',$RequestPath)){[void]$info.ArgumentList.Add($arg)}
 # Inherit the console so device codes and authentication instructions remain visible.
 $process=[Diagnostics.Process]::Start($info)
 try{
  while(-not $process.WaitForExit(1000)){
   $detail='Waiting for workload connection or response';$fraction=0;$s=$null
   if(Test-Path -LiteralPath $ProgressPath){try{$s=Get-Content $ProgressPath -Raw|ConvertFrom-Json;$detail=$s.Detail;$fraction=[double]$s.Completed/[math]::Max(1,$s.Total)}catch{}}
   if($s -and $s.Phase -eq 'Authentication'){Write-Progress -Id 1 -Activity 'M365 assessment' -Completed;continue}
   Update-AssessmentProgress $detail $fraction
  }
  if($process.ExitCode -ne 0){throw "Worker process exited with code $($process.ExitCode)."}
 }finally{if(-not $process.HasExited){$process.Kill($true)};$process.Dispose()}
}
