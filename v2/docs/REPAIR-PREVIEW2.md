# Repairing preview.1 collection failures

Version 2.0.0-preview.2 fixes defects found in a real preview.1 run. All changes stay under `v2/` and its validation workflow. The original toolkit at repository root remains unchanged. No customer data is included in this repository.

## What changed

| Issue | Correction | What still needs customer action |
|---|---|---|
| JSON date objects were converted to local strings and parsed again, shifting UTC by the workstation offset | Preserve DateTime/DateTimeOffset types and explicitly parse offset-bearing strings. Test the worker path in Mountain time. Keep Activity Explorer requests inside its last-30-day window | Rerun audit/activity; earlier audit results may have incorrect requested boundaries even if marked Collected |
| Activity Explorer fields were projected using names absent from the documented export schema | Keep documented RecordIdentity, Happened, User, FullUrl, RuleId, RuleName, RuleActions and other selected metadata; deduplicate by RecordIdentity; list SourceFields for schema inspection | Recollect. Previously discarded fields cannot be recovered from the old projected JSON/CSV. Free-form content is still excluded |
| Teams was blocked before authentication when an older module lacked DisableWAM | Modules older than 7.8.1 use their existing non-WAM interactive path. Newer commands use DisableWAM when available; otherwise a supported device-code option is selected explicitly | Complete Teams sign-in; Conditional Access and Teams authorization still apply |
| Commercial core SharePoint connection failed, while the later isolated DAG connection succeeded | Move the three Commercial SPO inventory collectors into the same isolated worker as DAG. Use one connection for tenant settings, sites, OneDrives and DAG | If sign-in still fails, perform the standalone SPO test below. The previous log alone cannot identify why OAuth failed |
| Every absent DAG export was labeled Failed | A successful empty report-list query is now NoExistingReport, distinct from authorization/query failures | Generate the desired report, wait for completion, then rerun IncludeDAG |
| Unsupported/duplicated DAG workload combinations | Omit OneDrive sensitivity-label query; mark OneDrive site-level EEEU NotApplicable; query combined Everyone/EEEU snapshot reports once without a Workload filter | Some special-group reports require the separate SharePoint Advanced Management Administrator role |
| Concealed UPNs and blank usage URLs looked like normal data | Add ReportIdentityQuality and a prominent HTML warning with observed blank/concealed counts | Review the tenant-wide Reports privacy setting; authorized changes and recollection are required to obtain identifiable usage exports |
| A missing Power Platform module looked like a tenant permission problem | Give explicit Windows PowerShell 5.1 installation guidance in the connection error | Install locally as shown below; Global Administrator cannot supply a missing workstation module |
| Troubleshooting required rerunning all successful core collectors | Add ExtensionsOnly to all six launchers | Use the targeted command below; this creates a separate report and does not merge old evidence |

## Restore identifiable usage exports

In Microsoft 365 admin center, go to **Settings > Org settings > Services > Reports**. If the customer authorizes identifiable reports, clear **Conceal user, group, and site names in all reports**, then save. This is a tenant-wide reporting privacy change and is audited. The script deliberately does not make it.

Microsoft says the setting also affects Graph and Power BI usage reports and can take a few minutes to apply. Export a small usage report to verify real UPNs/URLs before repeating the full collection. Existing concealed exports are not retroactively repaired and cannot be reliably matched to directory users by guessing or hashing names.

Directory `UserAssignments.csv` and direct `SharePointSites.csv` / `OneDriveSites.csv` are separate inventories. Their successful collection does not undo privacy masking in usage reports.

## Install Power Platform modules in the correct shell

Open **Windows PowerShell 5.1** (`powershell.exe`), using the same Windows account that runs the assessment. Run:

```powershell
Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser -Repository PSGallery
Install-Module Microsoft.PowerApps.PowerShell -Scope CurrentUser -Repository PSGallery -AllowClobber
Get-Module Microsoft.PowerApps.Administration.PowerShell,Microsoft.PowerApps.PowerShell -ListAvailable | Select-Object Name,Version,Path
```

Restart PowerShell 7 afterwards. Installing only in PowerShell 7's module directory does not establish that the Windows PowerShell compatibility session can find the module. Microsoft documents these modules as .NET Framework / Windows PowerShell modules.

## Test SharePoint independently and extract URLs

In a fresh **Windows PowerShell 5.1** window:

```powershell
Import-Module Microsoft.Online.SharePoint.PowerShell -ErrorAction Stop
Connect-SPOService -Url 'https://<tenant>-admin.sharepoint.com' -UseSystemBrowser $true
Get-SPOTenant -ErrorAction Stop | Select-Object SharingCapability
Get-SPOSite -Limit All -Detailed -ErrorAction Stop | Select-Object Url,Owner,Title,Template | Export-Csv -Path "$env:USERPROFILE\Downloads\SharePointSites.csv" -NoTypeInformation
Get-SPOSite -IncludePersonalSite $true -Limit All -Detailed -ErrorAction Stop | Where-Object Template -like 'SPSPERS*' | Select-Object Url,Owner,Title | Export-Csv -Path "$env:USERPROFILE\Downloads\OneDriveSites.csv" -NoTypeInformation
```

Replace the tenant placeholder. Confirm the customer account in the browser and wait for successful authentication. If Connect-SPOService still returns **No valid OAuth 2.0 authentication session exists**, record the module version, complete console error and matching Entra sign-in result. The exception itself does not prove a missing role, a blocked policy or a specific module defect. If UseSystemBrowser is absent, update the SPO module in this same Windows PowerShell 5.1 environment.

These commands export direct inventory without changing the Reports privacy setting. They do not include usage measures or a complete item-permission inventory.

## Generate and download DAG reports

The collector downloads **existing** DAG reports. NoExistingReport means the listing query returned none for that entity/scope; it does not prove there is no oversharing or that the tenant has no DAG reports of any kind.

In SharePoint admin center, go to **Reports > Data access governance**, choose the needed report and workload, and generate it. Alternatively, in the authenticated SPO shell, these Microsoft-documented commands start organization permission snapshots (they create report jobs, not permission changes):

```powershell
Start-SPODataAccessGovernanceInsight -ReportEntity PermissionedUsers -ReportType Snapshot -Workload SharePoint -CountOfUsersMoreThan 0 -Name 'AssessmentSharePointPermissions'
Start-SPODataAccessGovernanceInsight -ReportEntity PermissionedUsers -ReportType Snapshot -Workload OneDriveForBusiness -CountOfUsersMoreThan 0 -Name 'AssessmentOneDrivePermissions'
```

Only start a new job when the customer wants that report; do not repeatedly create existing snapshots. Record the returned ReportId. Microsoft documents up to five days for the first organization snapshot, subsequent completion within 24 hours, a 30-day rerun interval, and data up to 48 hours before generation. These constraints are specific to the organization permission snapshot, not every DAG report.

```powershell
Get-SPODataAccessGovernanceInsight -ReportID '<returned-report-guid>'
Export-SPODataAccessGovernanceInsight -ReportID '<completed-report-guid>' -DownloadPath "$env:USERPROFILE\Downloads"
```

Or rerun the toolkit with IncludeDAG after completion. For Everyone/EEEU detailed snapshot reports, Microsoft specifically documents the SharePoint Advanced Management Administrator role; do not assume Global Administrator alone satisfies that separate prerequisite. Applicable SAM entitlements and module versions also matter.

## Targeted rerun from v2/Commercial

After extracting the patched archive into a separate folder and reviewing/unblocking its scripts where required, run this one line with your values:

```powershell
.\Start-Interactive.ps1 -TenantId '<tenant-guid>' -CustomerName '<customer>' -AdminUPN '<admin-upn>' -SharePointAdminUrl 'https://<tenant>-admin.sharepoint.com' -Period D90 -ExtensionsOnly -IncludeSharePoint -IncludeDAG -IncludeTeamsPolicies -IncludePowerPlatform -IncludeAudit -IncludeActivityExplorer -DisableWAM -OutputRoot 'C:\Tools\M365Assessment\ReportsV2Repair'
```

ExtensionsOnly omits the core Graph/Purview/Defender collection and the automatic Copilot licensed usage report. In Commercial, SharePoint inventory now runs as an extension and is included by IncludeSharePoint. Government core SPO behavior is retained; ExtensionsOnly does not run that government core inventory. To refresh identifiable usage reports after changing the privacy setting, use a normal full run **without ExtensionsOnly**.

Activity Explorer covers at most 30 days. A D90 run will still report Incomplete for those two datasets when it successfully collects only the supported 30 days, with the reason and effective dates recorded. That is distinct from the fixed future-date error. Missing source columns remain absent rather than being fabricated.

Fabric, Endpoint recommendations, Dataverse bots, registry preview and item-permission scans run only when explicitly selected with their prerequisites. NotRequested is not an access failure. Compliance Manager, Insider Risk and full native DSPM/Security Copilot assessments remain unimplemented in this preview; changing admin roles does not add collectors.

## Validation boundary

Regression tests reproduce the UTC conversion under a non-UTC time zone, verify documented metadata retention, Teams parameter selection, DAG classification, and identity-quality detection. They use synthetic fixtures, not customer records. Original-file hashes and all launchers are checked in Windows CI. No live tenant access is available to the developer; successful tenant authentication and service results require a new authorized run.

## Microsoft sources

- [Usage report privacy and admin-center steps](https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/activity-reports)
- [Activity Explorer date window and exported column names](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/export-activityexplorerdata)
- [Teams authentication and WAM introduction](https://learn.microsoft.com/en-us/powershell/module/microsoftteams/connect-microsoftteams)
- [SPO browser authentication](https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/connect-sposervice)
- [DAG scopes, report generation, timing and special-role prerequisites](https://learn.microsoft.com/en-us/sharepoint/powershell-for-data-access-governance)
- [Power Platform module installation and Windows PowerShell requirements](https://learn.microsoft.com/en-us/power-platform/admin/powerapps-powershell)
