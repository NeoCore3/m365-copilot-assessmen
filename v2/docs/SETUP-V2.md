# Version 2 setup and permissions

Version 2 is an opt-in preview under `v2/`. The repository-root scripts are preserved. Use Windows PowerShell 7.4+ (`pwsh`), with Windows PowerShell 5.1 available for the SPO and Power Platform compatibility modules. Extract the whole repository ZIP; do not copy individual scripts into the original installation.

The original core collectors retain their connection behavior. New extension workloads run sequentially in fresh `pwsh -NoProfile` processes. Expect separate sign-ins. No module installation, app creation, consent grant, role assignment, policy change, or DAG report generation happens automatically.

## Modules

Keep the modules that already work for the core assessment. Add only modules needed for selected extensions:

| Switch | Module or authentication dependency |
|---|---|
| Core Graph, licensed Copilot v2 report, registry preview, item permissions | Microsoft.Graph.Authentication |
| IncludeDAG | Microsoft.Online.SharePoint.PowerShell, available to Windows PowerShell 5.1 |
| IncludeAudit, IncludeActivityExplorer | ExchangeOnlineManagement |
| IncludeTeamsPolicies | MicrosoftTeams |
| IncludePowerPlatform | Microsoft.PowerApps.Administration.PowerShell and its dependencies, available to Windows PowerShell 5.1 |
| IncludeFabric, IncludeEndpoint, IncludeAgents | Built-in REST client; customer-approved API application as below |

Install missing modules under the appropriate shell with `Install-Module -Scope CurrentUser`, after reviewing the package. The toolkit does not change execution policy. Follow your organization's signing policy; if downloaded files are blocked, review and unblock the trusted extracted files where policy permits. Group Policy execution restrictions still apply.

## Interactive API authentication

`ApiClientId` is the customer's approved public-client application for **Fabric, Endpoint and Dataverse**. It is separate from optional `ClientId`, which selects the Graph PowerShell client. Register the public client in the customer tenant, enable public-client device-code authentication, add only the delegated permissions below, and obtain customer admin consent where required. The customer must allow this authentication flow in Conditional Access. The script does not bypass a blocked flow; omit these extensions until an approved method is provisioned.

Sign in using the device code printed by this running script. Tokens are kept in worker memory; no refresh token is requested or cached by the native API client. Long-running API collection stops with a failure/incomplete status if its token expires. Rerun the selected workload. Module-managed caches are controlled by those Microsoft modules.

## Extension authorization matrix

An Entra role, API consent, workload RBAC, and a product license are different requirements. A successful sign-in alone does not establish access to a dataset. This matrix describes the new collectors; [SETUP.md](SETUP.md) documents retained core collectors.

| Collector | Interactive permissions and roles | Certificate mode |
|---|---|---|
| Fabric tenant settings and admin workspaces | Fabric Administrator plus Fabric delegated `Tenant.Read.All` | Supported by these APIs; approved service principal must satisfy Fabric tenant settings governing service-principal/admin API access |
| Fabric accessible capacities | Fabric delegated `Capacity.Read.All`; caller must have administrator/contributor access to returned capacities | Supported; only capacities accessible to the service principal are returned |
| Endpoint recommendations | WindowsDefenderATP delegated `SecurityRecommendation.Read`, with applicable Defender workload access and licensing | WindowsDefenderATP application `SecurityRecommendation.Read.All`, admin consent |
| Dataverse bot configuration | Dynamics CRM delegated `user_impersonation`; Dataverse security role with Read privilege on the Agent (`bot`) table at the required organizational scope in each selected environment | Application user in each environment with the required Dataverse role; app certificate registered in Entra |
| Graph agent registry (explicit beta opt-in) | Graph `AgentInstance.Read.All` plus Agent Registry Administrator, the documented least-privileged supported role | Graph application `AgentInstance.Read.All`, admin consent |
| Licensed Copilot report v2 | Graph `Reports.Read.All` and a supported report-reading role such as Reports Reader | Graph application `Reports.Read.All`, admin consent |
| Selected drive-item permissions | Graph `Files.Read.All`; delegated results remain limited by the signed-in user's access | Graph application `Files.Read.All`, admin consent. This is a broad grant: only enable after customer approval |
| DAG downloads/site reviews | SharePoint Administrator with applicable SAM/DAG entitlement and existing reports | Uses supported Connect-SPOService certificate parameters; customer must provision SPO tenant-administration app authorization. Graph file/site read consent does not authorize these cmdlets |
| Copilot audit search | Purview Audit Reader role group / View-Only Audit Logs role as appropriate, exposed through Exchange Online PowerShell | Not enabled in this preview; command-level unattended support remains unverified |
| Activity Explorer metadata | Explicit Purview Information Protection Reader role or another documented qualifying assignment; RBAC must expose Export-ActivityExplorerData | Not enabled in this preview |
| Teams configuration Get-Cs commands | Teams Administrator is a supported practical role for this set; narrower custom/read roles must be checked against the exact commands | Graph application `Organization.Read.All` plus appropriate directory RBAC assigned to the service principal. No non-Cs write permissions are requested by this collector |
| Power Platform admin inventory | Power Platform Administrator for tenant administration; scoped environment admins produce scoped results | Not enabled in this preview |

For SPO app-only authorization, use the customer's approved tenant-admin permission design and Microsoft's current connection requirements. This preview deliberately does not prescribe a tenant-wide write-capable app grant merely to obtain read-only report data. The presence of certificate parameters is not proof that every tenant or command permits the app.

The API certificate path uses `ClientId` and `CertificateThumbprint`, with an accessible, valid RSA private key in `Cert:\CurrentUser\My`. The public certificate must be registered on that app. It signs a short-lived PS256 client assertion and requests the resource's `.default` scope. No interactive fallback occurs in certificate mode. Audit, Activity Explorer and Power Platform report `AuthenticationUnverified` when selected in that mode.

## Cloud boundaries

Commercial, GCC and GCC High retain separate interactive/certificate launchers. **New extension collectors in this preview are enabled for Commercial only.** They report `CapabilityUnverified` in GCC/GCC High and make no Commercial fallback calls. This means implementation verification is pending, not that Microsoft necessarily lacks the capability. Existing cloud-aware core collectors continue as before.

## Commands

From the extracted repository root, the following is one line. Replace the placeholders; `ApiClientId` is required for the Fabric/Endpoint extensions:

```powershell
pwsh -NoProfile -File .\v2\Commercial\Start-Interactive.ps1 -TenantId '<tenant-guid>' -CustomerName '<customer>' -AdminUPN '<admin-upn>' -SharePointAdminUrl 'https://<tenant>-admin.sharepoint.com' -ApiClientId '<approved-public-client-guid>' -Period D90 -IncludePurview -IncludeDefender -IncludeSharePoint -IncludeFabric -IncludeDAG -IncludeTeamsPolicies -IncludePowerPlatform -IncludeAudit -IncludeActivityExplorer -IncludeEndpoint -DisableWAM -OutputRoot 'C:\Tools\M365Assessment\ReportsV2'
```

Add `-IncludeAgents -DataverseUrls 'https://<environment>.crm.dynamics.com'` for approved Dataverse environments. Add `-IncludeAgentRegistryPreview` only after beta use and its additional Graph permission are approved. Add `-IncludeItemPermissions -DriveIds '<drive-id>' -MaxItems 1000` for a bounded permissions scan. No environment or drive is guessed or automatically selected for a deep scan.

Certificate example (selected extensions only):

```powershell
pwsh -NoProfile -File .\v2\Commercial\Start-Certificate.ps1 -TenantId '<tenant-guid>' -CustomerName '<customer>' -ClientId '<app-guid>' -CertificateThumbprint '<thumbprint>' -Organization '<tenant>.onmicrosoft.com' -SharePointAdminUrl 'https://<tenant>-admin.sharepoint.com' -Period D90 -IncludePurview -IncludeDefender -IncludeSharePoint -IncludeFabric -IncludeDAG -IncludeTeamsPolicies -IncludeEndpoint -OutputRoot 'C:\Tools\M365Assessment\ReportsV2'
```

The new defaults are `MaxPages=200`, `MaxRows=100000` per dataset, and `MaxItems=1000` for the selected-drive scan. Hitting a limit preserves collected rows with `Incomplete`. The original core collectors retain their existing limits. Activity Explorer cannot supply D90 history: it exports up to 30 days and records `Incomplete` for a longer request. The licensed Copilot v2 report maps D30 to D28 explicitly; other reports retain D30.

## Review the output

Open `Assessment.html`, then `collection-status.csv`, `diagnostics.csv` and `coverage-v2.csv`. Raw JSON and formula-protected CSV are under `raw/` and `csv/`. Existing DAG reports are under `downloads/`; the corresponding dataset lists file paths, hashes, service statuses and download status. These are native service exports and have not been rewritten.

Each of the original 20 categories remains a review boundary. `PartialCoverage` indicates some evidence was obtained, not full automation or a passing control. `EvidenceRequired` means that category still needs evidence. `Collected` means a particular query completed within its declared scope, not that all tenant data is visible or a control is effective. `Derived` means an evidence index or allocation calculation. Preview registry results are not a universal agent inventory.

Imported evidence still requires matching tenant/cloud metadata as described in [EVIDENCE.md](EVIDENCE.md). It is labeled Imported, never independently verified. Keep the whole report folder together. Outputs contain customer configuration/identities; choose a customer-approved location outside the repository.

## Microsoft references checked for this implementation

- [Fabric tenant settings](https://learn.microsoft.com/en-us/rest/api/fabric/admin/tenants/list-tenant-settings), [admin workspaces](https://learn.microsoft.com/en-us/rest/api/fabric/admin/workspaces/list-workspaces), [accessible capacities](https://learn.microsoft.com/en-us/rest/api/fabric/core/capacities/list-capacities)
- [DAG listing](https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-spodataaccessgovernanceinsight), [DAG export](https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/export-spodataaccessgovernanceinsight), [site reviews](https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-spositereview)
- [Copilot report versions](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/api/admin-settings/reports/copilotreportroot-getmicrosoft365copilotusageuserdetail), [Graph registry beta](https://learn.microsoft.com/en-us/graph/api/agentregistry-list-agentinstances?view=graph-rest-beta), [drive item permissions](https://learn.microsoft.com/en-us/graph/api/driveitem-list-permissions)
- [Audit search](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/search-unifiedauditlog), [Activity Explorer export](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/export-activityexplorerdata), [Activity Explorer roles](https://learn.microsoft.com/en-us/purview/data-classification-activity-explorer)
- [Endpoint recommendations](https://learn.microsoft.com/en-us/defender-endpoint/api/get-all-recommendations), [Endpoint token audience](https://learn.microsoft.com/en-us/defender-endpoint/api/exposed-apis-create-app-webapp)
- [Dataverse bot fields](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/bot), [Power Platform PowerShell](https://learn.microsoft.com/en-us/power-platform/admin/powerapps-powershell), [Teams app authentication](https://learn.microsoft.com/en-us/microsoftteams/teams-powershell-application-authentication)
- [Device authorization](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code), [certificate assertion format](https://learn.microsoft.com/en-us/entra/identity-platform/certificate-credentials)
