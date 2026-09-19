# Microsoft 365 Copilot Assessment Toolkit

Read-only evidence collection for Windows PowerShell **7.4+ (pwsh)**, with an offline HTML assessment, charts, dataset CSVs, consolidated workstream CSVs and raw JSON evidence.

## Choose a cloud and authentication method

| Cloud | Interactive | Certificate |
|---|---|---|
| Commercial | Commercial/Start-Interactive.ps1 | Commercial/Start-Certificate.ps1 |
| GCC | Government/GCC/Start-Interactive.ps1 | Government/GCC/Start-Certificate.ps1 |
| GCC High | Government/GCCHigh/Start-Interactive.ps1 | Government/GCCHigh/Start-Certificate.ps1 |

The six entry points share a reporting engine to prevent drift. GCC uses Global Graph; GCC High uses USGov. No fallback to commercial endpoints is performed for GCC High. DoD is not included.

## Install prerequisites

Use a dedicated PowerShell process for one customer at a time. Install modules on the assessment workstation; the collector never installs software or grants consent automatically.

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
# Optional configuration collectors:
Install-Module ExchangeOnlineManagement -Scope CurrentUser
# Install the latest SharePoint module using Windows PowerShell 5.1:
powershell.exe -NoProfile -Command "Install-Module Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser"
```

The SPO module is loaded through the Windows PowerShell compatibility session. A current version supporting certificate authentication is required for that mode. Test module compatibility on your workstation before a customer engagement.

## Commercial: interactive

```powershell
./Commercial/Start-Interactive.ps1 -TenantId '<tenant-guid>' -CustomerName 'Customer' -Period D90
```

Add optional configuration collectors:
```powershell
./Commercial/Start-Interactive.ps1 -TenantId '<tenant-guid>' -CustomerName 'Customer' -AdminUPN 'assessor@customer.example' -IncludePurview -IncludeSharePoint -SharePointAdminUrl 'https://customer-admin.sharepoint.com' -IncludeDefender
```

## Commercial: unattended certificate

```powershell
./Commercial/Start-Certificate.ps1 -TenantId '<tenant-guid>' -CustomerName 'Customer' -ClientId '<app-guid>' -CertificateThumbprint '<thumbprint>' -Organization 'customer.onmicrosoft.com' -IncludePurview
```

Certificate mode has no interactive fallback. Provision the app, certificate and permissions in advance. The certificate with private key must be accessible in the execution account's CurrentUser certificate store. Use the same Windows identity for scheduled runs. Never put a private key or customer output in this repository.

## Government

Use the equivalent GCC or GCCHigh entry point and the appropriate tenant app registration and SharePoint admin URL. For example:

```powershell
./Government/GCC/Start-Interactive.ps1 -TenantId '<tenant-guid>' -CustomerName 'GCC Customer'
./Government/GCCHigh/Start-Certificate.ps1 -TenantId '<tenant-guid>' -CustomerName 'GCC High Customer' -ClientId '<government-app-guid>' -CertificateThumbprint '<thumbprint>'
```

See [permissions and cloud setup](docs/SETUP.md). GCC availability is not inferred solely from use of the Global endpoint.

## Output

Default: `%LOCALAPPDATA%/M365Assessment/<cloud>-<tenant>-<unique-run>/`.

- **Assessment.html**: offline report, evidence coverage chart, SKU allocation graph, explanatory tables, search and CSV links.
- **collection-status.csv**: authoritative dataset collection status.
- **diagnostics.csv**: service error summaries, error IDs, loaded module versions and troubleshooting guidance. Review for customer identifiers before sharing.
- **manifest.json**: tenant/cloud, period, timestamps and dataset provenance.
- **csv/<dataset>.csv** and **csv/Workstream-<name>.csv**: all collected rows, with nested data represented as JSON.
- **raw/<dataset>.json**: unmodified values serialized from collected objects, before CSV formula protection.

Keep the report folder together for CSV links. HTML previews show at most 100 rows per dataset; CSV exports contain all collected rows. Collection failures discard partial datasets and remain visible. Raw JSON and CSV can contain customer identifiers; this is not an anonymization tool.

## Coverage and limits

Automated: organization, SKUs/service plans, user assignments, collaboration usage, licensed Copilot activity, Conditional Access, security defaults, enterprise applications, Secure Score, Graph SharePoint settings, optional Purview policies/rules/labels, Defender for Office 365/EOP policies and rules, SPO tenant/site and OneDrive site settings.

[Evidence coverage](docs/COVERAGE.md) explicitly lists areas needing imported portal evidence: unlicensed Chat, prompt totals, Copilot optimization, SAM/DAG, item-level permissions, DSPM/AI, Compliance Manager, IRM, full Defender posture, Security Copilot, actual agent inventory, Copilot Studio, Power Platform and Fabric. Those areas are **not automatically collected in this version**. Import support is provided; no unavailable control is reported as disabled.

The report supports an assessment; it does not produce an automatic readiness verdict. It never changes policies, license assignments, sharing settings or report anonymization.

## Import portal exports

Place an original CSV named after its dataset ID in a local evidence directory, alongside `<Id>.metadata.json`. See [import instructions](docs/EVIDENCE.md). Pass `-EvidencePath 'C:/Assessments/Evidence'`. Exports retain their source period; they are not silently normalized into the requested API period.

## Validation

Run `./tests/Test-Toolkit.ps1` in pwsh. CI performs syntax and offline behavioral checks on Windows. **No customer tenant has been used for integration validation.** Before production use, validate the six applicable connection paths, API permissions and module versions in authorized test tenants. A green CI run does not demonstrate tenant access or service availability.

## Troubleshoot missing Purview, Defender or SharePoint data

See [connection troubleshooting](docs/TROUBLESHOOTING.md). Requested datasets whose connection failed are `BlockedByConnection`, not empty results. `CommandUnavailable` means the session did not expose a cmdlet; this can reflect module, workload RBAC or cloud/service availability. Other command errors remain `Failed`, with the service message in `diagnostics.csv`.

`-IncludeDefender` now opens an Exchange Online connection as well as collecting Graph Secure Score. In certificate mode, supply `-Organization` and provision Exchange application authorization/RBAC before enabling it. Existing Graph-only app consent is insufficient.
