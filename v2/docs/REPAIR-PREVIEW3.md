# Preview 3: readable evidence and visible collection progress

This release changes v2 only. It does not change tenant configuration or automatically enable extra collectors.

## Run prerequisites and the reported Graph error

The supplied October run loaded Graph Authentication 2.41.0 on PowerShell 7.5.2 and reported a missing System.Text.Json 10.0.0.0 dependency. The source of that missing dependency cannot be established from the report alone. This is a local module/runtime failure; granting tenant roles does not repair it.

This build defaults to Microsoft.Graph.Authentication 2.40.0, which was present in the earlier successful run. Install it side by side in PowerShell 7 as the same Windows user:

```powershell
Install-Module Microsoft.Graph.Authentication -RequiredVersion 2.40.0 -Scope CurrentUser -Repository PSGallery
```

Every launcher now starts a fresh `pwsh -NoProfile` process and imports the selected version explicitly. Use `-GraphModuleVersion 'x.y.z'` only to select another installed version you have validated. No modules are installed or uninstalled by the assessment. Missing modules remain actionable collection failures. This compatibility choice has not been live-tested in the customer tenant.

## Dashboard and exports

Open `Assessment.html` from the extracted report folder. It is self-contained, works offline, and does not load a CDN, fonts or analytics. It includes:

- Eight observed metric cards. Blocked/unrequested data is shown as Unavailable; a collected zero remains zero.
- Collection-outcome chart and SharePoint sharing-configuration chart, with explicit scope. Neither is a security or readiness score.
- Workstream navigation, search, status filters, dark mode and printing.
- Expandable dataset previews and links to readable CSV, original CSV and raw JSON. Preview limits are 50 rows, 20 columns and 2,000 characters per cell; full exports retain the source data.
- Source, collection time, requested/effective scope and explanations. Category summaries are included in status totals and explicitly labeled as such.

Use `readable/<dataset>.csv` for review. Objects become dotted columns; arrays become line-separated values with named fields. Booleans become Yes/No. Numeric enums are not guessed. Same-run user/label/SKU lookups add readable names while preserving the source ID. Blank fields remain blank. Raw evidence remains available in `raw/` and original per-dataset `csv/` files.

`readable/Workstream-*.csv` is a long-form table: dataset, status, record number, field and value with provenance. This avoids a JSON Data cell or thousands of sparse columns. Filter Dataset + RecordNumber to review a single record. `readable/Field-guide.csv` explains property paths and source attribution. A `[field N]` suffix preserves case-colliding source properties.

## Authentication and progress

Each connection announces its service, purpose, tenant, account and authentication mode before a prompt. The startup stage list shows what is planned. Isolated workers retain separate sign-in sessions to avoid module conflicts. Authentication/MFA can still recur for different services or individual Dataverse environments; this release does not promise a single sign-in or bypass customer policies. Certificate mode retains the existing collector/cloud restrictions.

Progress includes stage number, percentage of stages completed, current collector, elapsed time and a periodically refreshed `progress.json`. Worker progress identifies audit/activity dates/pages and DAG downloads. Percentage measures execution stages, not time, rows or evidence completeness. Core blocking module commands update at their boundaries; extension workers are monitored once per second.

ETA is unknown on the first run. A completed run with a matching tenant/cloud/authentication/period/stage selection, Graph version and limits supplies stage-duration estimates on the next run. ETA includes historical sign-in time and becomes unknown if the current stage exceeds its historical duration. It is approximate, not a service SLA. `stage-timings.csv` records actual stage durations. A progress value of 100% means report generation finished, even if some collectors failed.

## Reformat an existing run without signing in

From the repository's `v2` folder:

```powershell
pwsh -NoProfile -File .\Render-Report.ps1 -RunDirectory 'C:\Reports\ExistingRun' -OutputDirectory 'C:\Reports\ExistingRun-Readable'
```

OutputDirectory must be new and outside RunDirectory. The tool copies the run, preserves collection dates/statuses/raw evidence and rebuilds its readable exports and dashboard. Reformatting cannot recover data that was never collected. Share the entire output folder/ZIP so download links work.

## Gaps that remain explicit

- Fabric and Dataverse agents require their existing switches, approved API client and real environment URLs. They were NotRequested in the supplied run. This release does not silently grant permissions or select environments.
- The existing optional beta agent registry is not a complete current Agent 365 package inventory. Full catalog/detail migration remains outstanding.
- Microsoft Security Copilot configuration and full DSPM/Insider Risk portal dashboards remain unimplemented.
- Activity Explorer metadata is limited to the supported recent window; D90 produces Incomplete with the actual scope.
- DAG InProgress reports are listed as NotReady. NoExistingReport means the query returned no existing report. Ready reports that fail export now retain a sanitized ExportError instead of discarding the reason. The collector never starts report generation.
- Missing or concealed UPNs, blank site owners and unreturned URLs are not fabricated.

## Validation

Offline tests cover original-file preservation, all six launchers, collector limits/failure handling, nested fields, case collisions, CSV formula escaping, HTML injection escaping, missing-versus-zero metrics and first-run ETA behavior. Browser checks cover desktop/mobile layouts, filters and dark mode. No live tenant access is available during development.
