# Missing workload evidence

The older script discarded connection exception messages. Its generic "enable" text after a requested connection failed cannot identify whether the cause was WAM, a module dependency, workload RBAC, application consent, a cloud endpoint or Conditional Access. A new run is required.

## Update and run

Download branch `feature/assessment-toolkit` (or the branch containing the merged correction), extract the complete folder, and start a fresh **PowerShell 7.4+** window using `pwsh -NoProfile`. Do not mix module versions in an existing session. Use the Windows account that installed the modules and owns any certificate private key.

Install/update the prerequisites in that window as approved for your workstation:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
Install-Module PowerShellGet -Scope CurrentUser -Force -AllowClobber
Install-Module PackageManagement -Scope CurrentUser -Force
powershell.exe -NoProfile -Command "Install-Module Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser -Force"
```

Close and reopen PowerShell after installation. Change to the extracted repository directory. For Commercial interactive collection:

```powershell
$params = @{
    TenantId = '<customer-tenant-guid>'
    CustomerName = 'Customer'
    AdminUPN = 'assessor@customer.onmicrosoft.com'
    IncludePurview = $true
    IncludeDefender = $true
    IncludeSharePoint = $true
    SharePointAdminUrl = 'https://customer-admin.sharepoint.com'
}
.\Commercial\Start-Interactive.ps1 @params
```

Use the corresponding Government/GCC or Government/GCCHigh wrapper for those environments and the correct SharePoint suffix. Sign in to the intended customer for every workload. Interactive guest/GDAP routing is not implemented in these wrappers; use an appropriately authorized account in the customer tenant.

## Interpret the output

| Status | Meaning / next action |
|---|---|
| NotRequested | Corresponding Include switch was omitted. |
| BlockedByConnection | Requested workload could not connect. Read its connection row in diagnostics.csv first. |
| CommandUnavailable | Connection returned, but a requested command was unavailable. Verify loaded module, effective workload RBAC and service/cloud support. |
| Failed | The connection or query threw an error. Read Message, ErrorId and Guidance in diagnostics.csv. |
| Collected with 0 rows | Query succeeded and returned no rows; this does not independently establish policy absence across all scopes. |
| ManualRequired | Collector is not implemented for this evidence; import an authorized portal export. |
| UnsupportedCloud | Dataset is explicitly unsupported in the selected cloud. |

Diagnostics include exception summaries and loaded module versions, not full error dumps or authorization headers. Common token/password patterns are redacted, but messages can still include customer identifiers; review before sharing. A missing loaded module version may mean import failed. Check installed versions locally with `Get-Module -ListAvailable`.

## Match the fix to the error

- Missing module, assembly or REST dependency: check PowerShell/module compatibility and use a fresh process. Install prerequisites before reconnecting.
- WAM/window-handle error: run under the logged-in Windows user. Only for a confirmed WAM problem, add `-DisableWAM` to the interactive wrapper. The toolkit checks that the loaded connection command supports it. MFA and Conditional Access still apply. There is no automatic authentication fallback.
- Consent error: ask the customer to approve the required application permissions. Graph consent does not grant Exchange, Purview or SharePoint workload access.
- Access denied or missing Get command: ask the customer workload permissions administrator to validate effective read roles and scope. Do not assume Global Reader or SharePoint administration grants every Purview/Defender command.
- Conditional Access error: the customer reviews the matching Entra sign-in event and permitted access method.
- Certificate error: verify the app, certificate/private-key availability for the execution identity, Organization, workload application authorization and role assignments. Graph application permissions alone are insufficient.
- SharePoint failure: verify the tenant admin URL, current SPO module in Windows PowerShell 5.1 and supported authentication parameters. SAM/DAG portal reports remain manual imports.

The collector performs no consent, role assignment or policy changes. Fixes to reporting do not guarantee tenant authorization. Offline CI validates control flow, not live customer permissions.

## Microsoft documentation

- [Purview connections and prerequisites](https://learn.microsoft.com/en-us/powershell/exchange/connect-to-scc-powershell)
- [Exchange connections, cloud routing and WAM](https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-online-powershell)
- [Exchange module requirements](https://learn.microsoft.com/en-us/powershell/exchange/exchange-online-powershell-v2)
- [App-only Exchange and Purview authentication](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2)
- [Find Exchange cmdlet permissions](https://learn.microsoft.com/en-us/powershell/exchange/find-exchange-cmdlet-permissions)
- [SharePoint connection syntax](https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/connect-sposervice)

## Missing Exchange module and unsupported SharePoint browser parameter

If diagnostics reports `Modules_ModuleNotFound` for ExchangeOnlineManagement, both Purview and Defender for Office 365 connections are blocked locally, before sign-in. Install the module in **PowerShell 7** using the same Windows user who runs the assessment:

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Repository PSGallery
Get-Module ExchangeOnlineManagement -ListAvailable | Select-Object Name,Version,Path
```

If diagnostics reports that `UseSystemBrowser` is not recognized, the imported SPO command does not expose that parameter. The updated collector inspects command capabilities: it uses UseSystemBrowser when available, otherwise explicitly selects ModernAuth when supported. It never substitutes stored passwords or basic authentication. Unsupported certificate or government-endpoint parameters result in an actionable prerequisite error.

Update the SPO module in **Windows PowerShell 5.1**, under the same Windows user:

```powershell
Install-Module Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser -Repository PSGallery -Force
Get-Module Microsoft.Online.SharePoint.PowerShell -ListAvailable | Select-Object Name,Version,Path
```

Close all assessment shells after installation so old modules and compatibility proxies are unloaded. Open `pwsh -NoProfile`, then verify:

```powershell
Import-Module ExchangeOnlineManagement -ErrorAction Stop
Get-Command Connect-IPPSSession,Connect-ExchangeOnline
Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell -ErrorAction Stop
Get-Command Connect-SPOService -Syntax
```

A reported SPO version of 1.0 can describe the generated compatibility proxy, so do not infer the native module's version from that number. Use the Windows PowerShell 5.1 module listing above. After verification, rerun the assessment with the same customer parameters. Installing workstation modules does not grant customer permissions; any subsequent authorization error needs separate diagnosis.

For downloaded ZIPs under RemoteSigned, review the toolkit and unblock its .ps1 files before running. AllSigned environments need the organization's approved code-signing process.
