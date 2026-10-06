# Preview 5: Audit progress repair and visible DAG exports

Run **v2/Commercial/Start-Interactive.ps1**, not the original root-level Commercial launcher. The manifest records `2.0.0-preview.5`. Existing run folder names such as Preview6 do not establish the code version. Original v1 is unchanged.

## What changed

- Audit and other collectors no longer fail if progress.json is locked. Progress JSON is written to a unique temporary file then published by rename; reads permit replacement. Telemetry I/O is best effort. Actual query/export failures still affect dataset status.
- Removed the redundant `CopilotLicensedUsage` v1 request that returned 404. The existing `CopilotLicensedUsageV2` collector remains the single licensed-usage source, with its schema and ID unchanged. D30 maps to D28 for this API only. An older run's failure is not relabeled successful.
- DAG queries explicitly select Snapshot or RecentActivity and record entity, workload, report type and inventory timestamp. Only completed reports are downloaded. Missing and pending reports remain distinguishable.
- HTML shows each downloaded DAG CSV's actual data rows and dates, with a bounded preview. `dag-artifacts.csv` indexes the files and their individual row counts. Inventory counts refer to reports, not exposed sites; do not sum overlapping exports.
- Legacy AgentRegistryPreview no longer requests a deprecated Graph API or permission when selected; it explains the replacement choices. AgentCatalogDetails is package inventory, not an equivalent complete agent-instance registry.
- Console prints the optional workload switches before authentication. Missing API app/environment/drive inputs receive explicit warnings.

## Run

From the extracted `v2/Commercial` directory, replace the tenant/account/URL placeholders. PowerShell 7.4+ is required. Keep the previously working module installation; this update does not require reinstalling SPO.

```powershell
pwsh -NoProfile -File .\Start-Interactive.ps1 -TenantId '<tenant-guid>' -CustomerName '<customer>' -AdminUPN '<administrator-upn>' -SharePointAdminUrl 'https://<tenant>-admin.sharepoint.com' -GraphModuleVersion '2.40.0' -GraphAuthMode Browser -RequireGraph -Period D90 -IncludePurview -IncludeDefender -IncludeSharePoint -IncludePowerPlatform -IncludeTeamsPolicies -IncludeAudit -IncludeActivityExplorer -IncludeDAG -DisableWAM -OutputRoot 'C:\Tools\M365Assessment\ReportsV2-Preview5'
```

The baseline command intentionally has no invented API client, Dataverse environment or drive IDs. It does not request Fabric, Endpoint, catalog, or bots. To collect them, add the following **to the same command**, after configuring the prerequisites:

```powershell
-IncludeFabric -IncludeAgentCatalog -IncludeAgents -IncludeEndpoint -ApiClientId '<approved-public-client-application-id>' -DataverseUrls 'https://<approved-environment>.crm.dynamics.com'
```

For agreed item-permission scope, additionally append `-IncludeItemPermissions -DriveIds '<approved-drive-id>'`. This is bounded by MaxItems (default 1000), MaxPages (200), and MaxRows (100000). Increase limits only for an agreed scope; finite limits are not tenant-wide completeness.

| Dataset | Required selection / prerequisite | What it does not establish |
|---|---|---|
| FabricTenantSettings, FabricWorkspaces | IncludeFabric; approved public client ApiClientId; delegated Fabric Tenant.Read.All; Fabric administrator | Capacity/workspace overrides and all item permissions |
| FabricAccessibleCapacities | IncludeFabric; Capacity.Read.All; caller's capacity access | All capacities in the tenant |
| AgentCatalogDetails | IncludeAgentCatalog; Graph CopilotPackages.Read.All consent; eligible Agent 365 licensing and supported admin role | Unpublished bots or complete deployed agent instances |
| DataverseBots | IncludeAgents; ApiClientId; explicit DataverseUrls; delegated user_impersonation; environment/table read access | Other environments, full publication/security assessment |
| EndpointRecommendations | IncludeEndpoint; ApiClientId; delegated Defender for Endpoint SecurityRecommendation.Read; workload access/licensing | All Defender XDR configuration |
| ScopedItemPermissions | IncludeItemPermissions; explicit approved DriveIds; Graph Files.Read.All and drive access | Full SharePoint ACLs/inheritance across the tenant |

ApiClientId is the Entra **Application (client) ID**, not Object ID or a secret. The app must permit public-client device-code authentication and the customer must approve its scopes. Fabric/Endpoint/Dataverse use separate device-code sign-ins and display which resource is requesting authentication. Conditional Access still applies. Graph `-ClientId` is a separate optional custom Graph application setting. See [SETUP-V2.md](SETUP-V2.md) and [RUN-PREVIEW4.md](RUN-PREVIEW4.md).

Find the actual Dataverse environment URL in Power Platform admin center > Environments > select environment > Environment URL. Use the approved environment's regional crm host; do not derive it from the tenant name. NotRequested means the switch was absent, not an authentication failure.

## DAG and SAM: what to expect

- `DAGBothEveryone`, `DAGBothEveryoneExceptExternalUsers`, and SharePoint/OneDrive `PermissionedUsers` correspond to special-group and site-permission snapshot exports. Open their downloaded CSV previews, not only report inventory rows.
- Header-only downloaded CSVs have zero data rows for that **report's scope/date**. They do not mean the download failed or that the tenant has no risks.
- Recent-activity sharing-link and EEEU reports have service-defined windows, separate from D90. A report generated after the assessment cannot appear in the earlier run.
- `NoExistingReport`: query returned no report for the recorded entity/workload/type. Generate the needed scoped report in the admin center, wait until completed, then rerun IncludeDAG. If the same exact report/date is visible but still missing, compare the recorded query and ReportId with `Get-SPODataAccessGovernanceInsight -ReportID '<report-guid>'`; preserve that response for diagnosis.
- `Incomplete` with NotReady: generation is pending; rerun after completion. ExportFailed: inspect ExportError. The script never calls Start/Set cmdlets to enable data collection or create policies implicitly.
- OneDrive EEEU **site-level activity** is unsupported; use its item-level activity report or the combined special-group snapshot. PermissionsReport is a distinct user-scoped report, not the PermissionedUsers tenant snapshot.
- **SAM Content Management Assessment is not fully reproduced.** DAG exports are supporting evidence, not the same as the portal's lifecycle/oversharing dashboard and recommendations. No supported public collector for that entire dashboard was verified for this build. Open SharePoint admin center > Advanced Management > Content Management Assessment > View recommendations and retain dated site lists/exports or screenshots. For lifecycle reports, open Policies > Site lifecycle management > the inactive-site or ownership policy > its execution report and download the available CSV. Do not create/activate policies just to satisfy this assessment: activation can notify owners or enforce actions.

## Remaining coverage labels

PartialCoverage is an assessment category, not a failed API call. It identifies evidence beyond the collected datasets. A successful query cannot prove policy effectiveness or full tenant scope.

| Category | Available evidence / alternative |
|---|---|
| CopilotPrompts | CopilotLicensedUsageV2 supplies licensed-user prompt counts. For conversation content use an authorized Purview eDiscovery process, subject to retention and access. |
| CopilotChat | Use Microsoft 365 admin center usage reports for the unlicensed Chat population, retaining dates and population. Historical audit events plus today's license assignments do not establish historical licensing. |
| CopilotOptimization | Reconcile assignments and usage, then review native portal recommendations. Derived allocation is not the native optimization report. |
| Activity Explorer | Maximum last 30 days; D90 cannot restore older Activity Explorer events. Use D30 for this workload or retain recurring exports. Audit is a separate source, not an equivalent replacement. |
| CopilotAuditActivity | Deduplicated CopilotInteraction metadata only, within accessible retention. Pagination limits, service ingestion, and search completeness still apply. The progress-lock repair removes a local defect, not these service limits. |
| Other categories | See next-actions.csv and [COVERAGE-V2.md](COVERAGE-V2.md). Imports with tenant/date/scope metadata remain explicitly Imported, not independently validated. |

To attach reviewed portal CSV evidence to a category, use `-EvidencePath`. Name files `<category-id>.csv` and `<category-id>.metadata.json`, for example AdvancedManagement.csv and AdvancedManagement.metadata.json. Metadata must include TenantId, Cloud, Source, CollectedAtUtc (ISO timestamp), and Scope. Preserve the original export and clearly describe its limited scope; one imported file does not certify the whole category.

## Rebuild an existing HTML without signing in

From `v2/Commercial`, this creates a new copy and leaves the original run intact:

```powershell
pwsh -NoProfile -File ..\Rebuild-Report.ps1 -ReportDirectory '<existing-run-folder>' -OutputDirectory '<new-unused-review-folder>'
```

The new HTML previews existing DAG downloads and writes dag-artifacts.csv. It does not recover missing Audit rows, collect skipped workloads, or relabel prior failures. A fresh assessment is required for those.

## Validation and primary references

Offline tests cover an exclusively locked progress file during Audit, telemetry recovery, preserved real failures, DAG pending/missing/filter behavior, CSV row counts and bounded previews, all six launchers, original v1 preservation, API pagination and authentication console output. They do not authenticate to a customer tenant.

- https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/api/admin-settings/reports/copilotreportroot-getmicrosoft365copilotusageuserdetail
- https://learn.microsoft.com/en-us/sharepoint/powershell-for-data-access-governance
- https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-spodataaccessgovernanceinsight
- https://learn.microsoft.com/en-us/sharepoint/content-management-assessment
- https://learn.microsoft.com/en-us/sharepoint/inactive-site-policy
- https://learn.microsoft.com/en-us/sharepoint/site-ownership-policy
- https://learn.microsoft.com/en-us/rest/api/fabric/admin/tenants/list-tenant-settings
- https://learn.microsoft.com/en-us/rest/api/fabric/admin/workspaces/list-workspaces
- https://learn.microsoft.com/en-us/graph/api/resources/agentregistry?view=graph-rest-beta
