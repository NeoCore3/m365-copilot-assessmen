# Running v2 preview.4

## Authentication display hotfix

The launcher now inherits console handles directly. Graph sign-in messages are immediately written/flushed to the console, and progress bars are cleared while authentication is waiting. This fixes output-handling weaknesses; it does not establish the cause of a customer tenant sign-in failure.

If DeviceCode still waits without displaying a code, stop it and use `-GraphAuthMode Browser`. To isolate authentication before a full run, run from v2/Commercial:

```powershell
pwsh -NoProfile -File ..\Test-GraphConnection.ps1 -TenantId <tenant-guid> -GraphAuthMode Browser
```

The test requests the core Graph permissions, verifies tenant context and exits. It does not collect the full assessment or share its process token with the later run. A failed connection prints the underlying error; preserve that error or the full run diagnostics.csv for diagnosis. Source code alone does not identify a tenant/network authentication failure.


The collector can export the implemented API/PowerShell datasets for which the caller has access. It cannot promise every portal report, recover data beyond service retention, generate business approvals, or infer an enforcement outcome from a policy snapshot. `config/remediation.json` documents alternatives for all 20 assessment categories. No full Compliance Manager, Insider Risk, native DSPM posture, or Security Copilot configuration collector is implemented. These are implementation limitations, not claims that Microsoft offers no APIs.

## Changes

- `-GraphAuthMode Browser|DeviceCode` controls Graph sign-in in the core and Graph workers. Default Browser preserves existing behavior. DeviceCode displays the Microsoft sign-in URL/code. Use it only when tenant policy permits. It does not bypass consent, MFA, or Conditional Access. `-DisableWAM` is for Exchange/Purview and does not change Graph authentication.
- `-RequireGraph` stops before other workloads if the initial Graph connection fails, writes diagnostics and exits unsuccessfully. Recommended for a complete baseline run. Without it, independent workloads continue as before. An early-stopped report is not a completed assessment.
- DAG export retries once when the SPO module creates a filename containing a missing child directory, such as a label containing a backslash. Only CSV paths contained in the report download directory are eligible. Other errors remain visible. Tenant labels are never changed.
- `-IncludeAgentCatalog` collects current Graph v1.0 catalog packages and details in a separate worker. It preserves inventory if some detail calls fail, follows pagination, and reports limits/errors as incomplete. Default limits: 200 pages, 1,000 packages (`MaxItems`), 100,000 rows. Catalog rows can include apps; do not call the total an agent count. Unpublished/unregistered agents outside the catalog require separate inventory.
- `next-actions.csv` gives the evidence status, entry type, reason and action for every result. HTML includes next actions and direct links to downloaded DAG artifacts. Dataset counts now exclude connection records, derived analyses and assessment-coverage summaries; all entries remain visible in the explorer.

## Install and run

Download the updated branch/commit ZIP into a **new folder**. Keep the previous working copy. Use PowerShell 7.4 or later (`pwsh`), not Windows PowerShell 5.1, for the launcher. Go to the extracted **v2/Commercial** folder.

Install the Graph Authentication version used by this build, if not already installed:

```powershell
Install-Module Microsoft.Graph.Authentication -RequiredVersion 2.40.0 -Scope CurrentUser -Repository PSGallery
```

The pin addresses a previously observed local dependency problem; it is not a guarantee of tenant authentication. Other workload modules are still required: ExchangeOnlineManagement, MicrosoftTeams, Microsoft.PowerApps.Administration.PowerShell, and Microsoft.Online.SharePoint.PowerShell. Keep an already working SPO installation; avoid reinstalling it for an authentication cancellation. Commercial SPO uses Windows PowerShell compatibility in an isolated worker.

After reviewing/trusting the downloaded source, unblock its scripts (from v2/Commercial):

```powershell
Get-ChildItem -LiteralPath '..' -Recurse -Filter '*.ps1' | Unblock-File
```

This removes the downloaded-file mark. It does not override a customer signing policy. If AllSigned or a managed policy requires signed scripts, arrange approved signing rather than bypassing that policy.

Set customer-specific values locally:

```powershell
$TenantId = Read-Host 'Customer tenant GUID'
$CustomerName = Read-Host 'Customer report name'
$AdminUPN = Read-Host 'Customer administrator UPN'
$SharePointAdminUrl = Read-Host 'SharePoint admin URL (https://tenant-admin.sharepoint.com)'
```

Run the baseline and configured workloads, stopping immediately if core Graph sign-in fails:

```powershell
pwsh -NoProfile -File .\Start-Interactive.ps1 -TenantId $TenantId -CustomerName $CustomerName -AdminUPN $AdminUPN -SharePointAdminUrl $SharePointAdminUrl -GraphModuleVersion '2.40.0' -GraphAuthMode DeviceCode -RequireGraph -Period D90 -IncludePurview -IncludeDefender -IncludeSharePoint -IncludePowerPlatform -IncludeTeamsPolicies -IncludeAudit -IncludeActivityExplorer -IncludeDAG -DisableWAM -OutputRoot 'C:\Tools\M365Assessment\ReportsV2'
```

Follow every named service sign-in prompt. Graph worker sign-ins are separate because workers isolate incompatible modules. For Graph device-code authentication, open the printed Microsoft URL and enter the code displayed in that console. Choose the customer tenant account. Do not close/cancel a prompt that is still required. If device-code flow is blocked, use `-GraphAuthMode Browser` and resolve the Entra sign-in-log error with the customer; do not relax their policy.

`D90` remains appropriate for supported 90-day usage/audit sources. Activity Explorer will accurately report its shorter window as incomplete. Choosing `D30` requests a matching Activity Explorer window but does not restore older data; Copilot usage v2 maps D30 to its documented D28 period.

## Optional workloads: consent and inputs first

Adding a switch requests a collector. It cannot grant access or purchase licenses.

| Option | Additional requirements | Scope / alternative |
|---|---|---|
| `-IncludeFabric` | Approved public-client application ID via `-ApiClientId`; delegated Fabric `Tenant.Read.All` and `Capacity.Read.All`; Fabric administrator for admin endpoints and access to capacities | Tenant settings, admin workspaces, accessible capacities. Review remaining overrides, item permissions and activity in Fabric admin portal. |
| `-IncludeAgents` | Same `-ApiClientId`, delegated Dataverse `user_impersonation`, explicit `-DataverseUrls` and bot read access in each environment | Dataverse bot configuration; review publication/sharing, connectors and knowledge sources in Copilot Studio. |
| `-IncludeAgentCatalog` | Graph `CopilotPackages.Read.All` consent; Microsoft Agent 365 license; Microsoft's Agent 365 guide lists AI administrator or Global administrator for these APIs | Current package inventory and per-package details; use Microsoft 365 admin center agent inventory if the API is unavailable. |
| `-IncludeEndpoint` | `-ApiClientId`, delegated Defender for Endpoint `SecurityRecommendation.Read`, workload access and licensing | Endpoint recommendations, not all Defender XDR settings. |
| `-IncludeItemPermissions` | Explicit approved `-DriveIds`; Graph scopes requested by the collector and access to those drives | Bounded scan of Graph-visible permissions. Inspect full SharePoint ACL/inheritance separately. |

`ApiClientId` is the Entra Application (client) ID of a customer-approved app configured for public-client device-code authentication, not its Object ID or a secret. Dataverse URLs are the actual environment origins from Power Platform admin center (for example, `https://environment.crm.dynamics.com`; use the real region suffix). Existing PowerPlatformEnvironments JSON may contain `Internal.properties.linkedEnvironmentMetadata.instanceUrl`; verify it against the approved environment. Never guess URLs from the tenant name.

`-ClientId` selects an optional custom Graph application and is separate from `-ApiClientId`. If you use a custom Graph app, consent its required delegated Graph permissions (including CopilotPackages.Read.All when requested) and enable the intended interactive/public-client authentication. Without ClientId, the Graph SDK uses its default application; the customer must consent the requested scopes.

For the additional configured workloads, append to the baseline command after replacing these placeholders:

```powershell
-IncludeFabric -IncludeAgents -IncludeAgentCatalog -IncludeEndpoint -ApiClientId '<approved-application-client-id>' -DataverseUrls 'https://<approved-environment>.crm.dynamics.com'
```

The line above is an argument suffix, not a standalone command. Do not include Endpoint or AgentCatalog until their separate permissions/licensing are ready. `-IncludeAgentRegistryPreview` remains a legacy compatibility option; Microsoft documents its replacement. Use the current catalog collector for new inventory work.

## DAG reports that do not exist yet

`NoExistingReport` means the service returned no report for that query. A Global Administrator cannot download a report that has not been generated. Create the required report through **SharePoint admin center > Reports > Data access governance**, or use `Start-SPODataAccessGovernanceInsight` with the entity, workload and approved scope. Review licensing, service generation quotas and collection status first. The assessment does not silently create reports or enable audit collection.

For example, in a connected SPO session, generating a SharePoint recent-activity Anyone-links report is a separate action:

```powershell
Start-SPODataAccessGovernanceInsight -ReportEntity SharingLinks_Anyone -Workload SharePoint -ReportType RecentActivity
```

Record the returned ReportId, wait until the report is ready, then rerun the collector with `-IncludeDAG`. `PermissionsReport` needs an approved user UPN list; sensitivity-label reports need the selected label GUID/name. There is no meaningful universal scope for these. Recent-activity reports have their own reporting windows, independent of the script's D90 selection. Some snapshot reports take days to generate. OneDrive EEEU site-level reports are unsupported; use the supported item-level report instead.

If SPO still cannot export a label-named file, download it in the SharePoint admin center and retain it with its report ID/date/scope. Do not rename production labels just to repair an export filename.

## Remaining assessment evidence

See `config/remediation.json` and each run's `next-actions.csv` for all 20 categories. Key alternatives:

- Compliance Manager: export the assessment to Excel in Microsoft Purview.
- Insider Risk: authorized reviewer captures policy, analytics and case evidence in Purview, respecting pseudonymization/access restrictions.
- Native DSPM / DSPM for AI: capture the relevant portal assessments and recommendations, with dates and scope. Activity metadata is supporting evidence, not the native posture assessment.
- Security Copilot: review roles, capacity, plugins/connections and workspace settings in the service. Plugin access has its own authorization.
- DLP effectiveness: customer-approved enforcement tests and policy-scope review. A script reading configuration cannot establish an enforcement outcome.
- Teams: review effective assignments and app-centric access separately from policy definitions.
- Business expansion gates: designated owners record their decisions; the derived index is not approval.

Government launchers and certificate launchers remain separate. New extensions retain their government capability guards; this release does not claim Commercial APIs work in GCC/GCC High. Certificate support is limited to collectors marked for it; unattended runs do not fall back to interactive prompts.

## Validation and sources

Offline tests cover path containment, DAG retry, catalog paging/detail failures and bounds, launcher parameters, report classification, original v1 preservation and previous collector regressions. These tests do not exercise a live customer tenant. A complete successful collection must still be established by its new `diagnostics.csv`, `collection-status.csv`, per-row statuses and source scope.

- [Graph authentication](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.authentication/connect-mggraph)
- [Activity Explorer export and 30-day limit](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/export-activityexplorerdata)
- [DAG generation, scope, status and download](https://learn.microsoft.com/en-us/sharepoint/powershell-for-data-access-governance)
- [Fabric tenant settings API](https://learn.microsoft.com/en-us/rest/api/fabric/admin/tenants/list-tenant-settings)
- [Agent catalog and details](https://learn.microsoft.com/en-us/microsoft-agent-365/admin/graph-api)
- [List packages: permissions, licensing, cloud support](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/api/admin-settings/package/copilotpackages-list)
- [Package details](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/api/admin-settings/package/copilotpackagedetail-get)
- [Legacy registry replacement notice](https://learn.microsoft.com/en-us/graph/api/resources/agentregistry?view=graph-rest-beta)
- [Compliance Manager assessment export](https://learn.microsoft.com/en-us/purview/compliance-manager-assessments)
- [Security Copilot authentication and roles](https://learn.microsoft.com/en-us/copilot/security/authentication)
