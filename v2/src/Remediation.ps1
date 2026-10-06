function Get-AssessmentNextAction {
 param($Result,$CoverageActions)
 if($CoverageActions.Contains($Result.Id)){return $CoverageActions[$Result.Id]}
 if($Result.Status -eq 'Derived'){return 'No recollection required for this derived index. Review its source datasets; derived does not mean independently verified.'}
 if($Result.Id -eq 'AgentRegistryPreview'){return 'Legacy Graph registry APIs are deprecated. Use -IncludeAgentCatalog for catalog package details and -IncludeAgents with approved DataverseUrls for bots. Reconcile agent instances separately in Microsoft 365 admin center; packages are not agent instances.'}
 if($Result.Status -eq 'NotApplicable'){return 'No retry required for this unsupported report type. See the explanation for the supported alternative.'}
 if($Result.Id -eq 'GraphConnection' -or ($Result.Status -eq 'BlockedByConnection' -and $Result.Source -match '^/|Licenses dataset')){
  return 'Read GraphConnection in diagnostics.csv. Complete Graph sign-in; for a dismissed browser prompt use -GraphAuthMode DeviceCode if permitted by tenant policy. Add -RequireGraph to stop before other workloads if core Graph sign-in fails. An authentication cancellation is not evidence of missing administrator roles.'
 }
 if($Result.Id -like 'DAG*'){
  if($Result.Status -eq 'NoExistingReport'){return 'Generate this report entity/workload in SharePoint admin center > Reports > Data access governance (or Start-SPODataAccessGovernanceInsight with an approved scope). Wait for completion and rerun -IncludeDAG. Generation is separate; this collector only downloads existing reports.'}
  if($Result.Status -eq 'Incomplete'){return 'Inspect each raw report row: ServiceStatus, ExportStatus and ExportError. Pending service reports require a later retry. Filename-directory failures have a contained retry in preview.4. Use the native admin-center download if the module still fails.'}
  if($Result.Status -eq 'Collected'){return 'Open the linked files under downloads. The inventory row count is the number of reports, not exposed sites/items.'}
 }
 if($Result.Id -in @('AIActivityMetadata','DlpActivityMetadata') -and $Result.Status -eq 'Incomplete'){
  return 'Read the effective StartUtc/EndUtc and error. Activity Explorer retains up to 30 days; -Period D90 cannot recover older rows. Use D30 for a matching request, retain recurring exports going forward, or use Purview Audit for supported audit events within available retention (not an equivalent Activity Explorer dataset).'
 }
 if($Result.Id -eq 'AgentCatalogDetails' -and $Result.Status -ne 'Collected'){return 'Enable -IncludeAgentCatalog with Graph CopilotPackages.Read.All admin consent, an eligible Agent 365 license and the required admin role. For partial results inspect DetailStatus/DetailError and limits. If unavailable, review agent inventory in Microsoft 365 admin center and export approved Dataverse bots.'}
 if($Result.Status -eq 'NotRequested'){
  if($Result.Id -like 'Fabric*'){return 'Add -IncludeFabric -ApiClientId <approved-public-client-id>; configure delegated Fabric Tenant.Read.All and Capacity.Read.All and appropriate workload access. See docs/RUN-PREVIEW4.md.'}
  if($Result.Id -like 'DataverseBots*'){return 'Add -IncludeAgents -ApiClientId <approved-public-client-id> -DataverseUrls <approved-environment-URLs>. Configure Dataverse delegated user_impersonation and per-environment bot read access.'}
  if($Result.Id -eq 'EndpointRecommendations'){return 'Add -IncludeEndpoint -ApiClientId <approved-public-client-id> with delegated SecurityRecommendation.Read and Defender for Endpoint workload access/licensing.'}
  if($Result.Id -eq 'AgentRegistryPreview'){return 'This is an optional legacy preview inventory, not complete Agent 365 coverage. Reconcile Microsoft 365 admin center inventory and approved Dataverse bot exports; see the documented limitation.'}
  if($Result.Id -eq 'ScopedItemPermissions'){return 'Add -IncludeItemPermissions -DriveIds <approved-drive-IDs> only for the agreed scope. Review MaxItems/MaxPages limits; it does not export every SharePoint ACL.'}
  return $Result.Explanation
 }
 if($Result.Status -in @('Failed','BlockedByConnection','CommandUnavailable')){return 'Use the exact service error in diagnostics.csv to resolve this workload connection/command, then rerun. Check consent and workload roles only when the error establishes an authorization problem.'}
 if($Result.Status -eq 'Collected'){return 'Collection completed for the documented scope. Review dates, returned records and exclusions; this is not an effectiveness verdict.'}
 return $Result.Explanation
}

function Get-AssessmentActions {
 param($Manifest)
 $coverage=Get-Content (Join-Path $PSScriptRoot '../config/remediation.json') -Raw|ConvertFrom-Json -AsHashtable
 foreach($r in $Manifest.Results){
  $type=if($coverage.Contains($r.Id)){'Assessment coverage'}elseif($r.Workstream -eq 'Connection'){'Connection'}elseif($r.Status -eq 'Derived' -or $r.Id -eq 'LicenseAllocationIndicators'){'Derived analysis'}else{'Dataset'}
  [pscustomobject]@{Id=$r.Id;EntryType=$type;Workstream=$r.Workstream;Status=$r.Status;RowCount=$r.RowCount;Explanation=$r.Explanation;NextAction=(Get-AssessmentNextAction $r $coverage)}
 }
}
