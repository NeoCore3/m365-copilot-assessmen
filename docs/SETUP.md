# Authentication, permissions and cloud setup

## Graph permissions

The same names are delegated scopes for interactive mode and application permissions for certificate mode. Only request permissions for the collectors you run. The default set below supports the core Graph collectors. Defender scopes are requested interactively only with IncludeDefender.

| Data | Graph permission |
|---|---|
| Organization | Organization.Read.All |
| SKU inventory | LicenseAssignment.Read.All |
| User assignments | User.Read.All |
| Usage reports including licensed Copilot | Reports.Read.All |
| Conditional Access / security defaults | Policy.Read.All |
| Enterprise application inventory | Application.Read.All |
| SharePoint Graph settings | SharePointTenantSettings.Read.All |
| Optional Secure Score | SecurityEvents.Read.All |

Admin consent is required where applicable. Delegated access also requires supported directory/workload roles; scope consent alone is insufficient. Reports Reader is a typical starting role for usage. Conditional Access and other settings can require additional supported reader roles. Do not default to Global Administrator for collection.

The default interactive path uses the Microsoft Graph PowerShell client. Supply ClientId to use a customer-approved public-client application; configure its supported interactive redirect URI and delegated permissions first. Certificate mode uses a confidential app registered in the selected cloud, with the public certificate uploaded and the required application permissions consented.

## Optional workloads

Use Windows PowerShell **7.4 or later (pwsh)** for this toolkit and a compatible current ExchangeOnlineManagement module. Recent ExchangeOnlineManagement releases require PowerShell 7.4 or later. Install PowerShellGet and PackageManagement prerequisites for REST connections. Windows PowerShell 5.1 is used only for the SPO compatibility module.

Defender: `IncludeDefender` uses Graph for Secure Score and Exchange Online PowerShell for Defender for Office 365/EOP policy configuration. The signed-in account must have effective Exchange RBAC exposing the listed Get commands; portal access or a Defender Unified RBAC assignment alone does not establish PowerShell authorization. Have the customer permissions administrator validate cmdlet access against the requested read-only role assignments using Microsoft's [cmdlet permissions procedure](https://learn.microsoft.com/en-us/powershell/exchange/find-exchange-cmdlet-permissions). Certificate mode additionally requires Exchange.ManageAsApp with admin consent and supported Exchange application RBAC/directory-role assignments, plus Organization. Do not substitute Graph permissions for Exchange permissions. This release adds no Graph scopes.

Purview: install ExchangeOnlineManagement, connect using an authorized account with the specific view/read roles exposing the requested Get-* cmdlets. Application mode additionally requires Exchange.ManageAsApp and appropriate workload RBAC/service-principal role configuration. Graph consent does not authorize Purview. Organization must be the target tenant's initial domain. This toolkit does not grant any permission or create an app.

SharePoint: a current SPO management module is required; interactive collection requires the appropriate SharePoint administrative role. Certificate access requires SharePoint application authorization for the tenant-administration cmdlets; Graph Sites.Read.All alone does not authorize SPO CSOM administration. Validate current Microsoft requirements, approved app permissions and support in the target cloud before enabling. This release does not prescribe tenant-wide write-capable SharePoint grants as a default. If the required access cannot be approved, omit IncludeSharePoint and use authorized portal evidence. The collectors themselves only issue Get commands.

Use a dedicated process and an account in the intended customer tenant for optional interactive workload connections. Confirm the customer identity in each sign-in dialog. Graph validates its tenant and environment; optional workload identity must also be verified by the operator.

## Cloud routing

| Profile | Graph SDK environment | Graph root | Identity authority |
|---|---|---|---|
| Commercial | Global | graph.microsoft.com | login.microsoftonline.com |
| GCC | Global | graph.microsoft.com | login.microsoftonline.com |
| GCC High | USGov | graph.microsoft.us | login.microsoftonline.us |

GCC High uses the government compliance PowerShell endpoint and .sharepoint.us URLs. GCC uses the standard compliance endpoint. Profiles do not change or certify data residency. No DoD profile is supplied.

The licensed Copilot usage API is explicitly skipped for GCC High based on documented availability. Other endpoint authorization, licensing and rollout differences remain visible as collection failures requiring review. The toolkit does not silently retry against a different cloud.

## Unattended operation

Use a dedicated customer application and execution identity. Upload the public certificate to that application, install its private key in the execution account's certificate store, grant approved permissions, then perform a test run.

Configure Task Scheduler to invoke pwsh.exe with -NoProfile -File and the certificate entry point. Set the output directory outside the repository. Schedule creation is deliberately an operator task. Monitor certificate expiry and collection-status.csv. Never use an interactive fallback in unattended jobs.

## Microsoft references

- [National cloud endpoints](https://learn.microsoft.com/en-us/graph/deployments)
- [Graph SDK national clouds](https://learn.microsoft.com/en-us/graph/sdks/national-clouds)
- [Copilot usage API and cloud availability](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/api/admin-settings/reports/copilotreportroot-getmicrosoft365copilotusageuserdetail)
- [Purview PowerShell connections](https://learn.microsoft.com/en-us/powershell/exchange/connect-to-scc-powershell)
- [Exchange and Purview app-only authentication](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2)
- [SharePoint connections and certificate parameters](https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/connect-sposervice)

API definitions were checked during implementation on September 17, 2026. Recheck platform documentation before each engagement.
