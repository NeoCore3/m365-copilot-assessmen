# v2 preview.5 — Audit repair and DAG report contents

Read [RUN-PREVIEW5.md](docs/RUN-PREVIEW5.md) for current commands, optional workload prerequisites, verified fixes and remaining portal exports. Progress-file locks no longer interrupt collection; obsolete duplicate Copilot v1 queries are removed; DAG CSV contents and per-file row counts are visible in HTML. Use Rebuild-Report.ps1 to review an existing run without authentication. Original v1 remains unchanged.

# v2 preview.4 — collection recovery and agent catalog

Read [RUN-PREVIEW4.md](docs/RUN-PREVIEW4.md) for current commands, prerequisites and alternatives. Adds Graph device-code selection and fail-fast option, contained DAG filename retry, modern agent catalog/details, per-entry next actions, and separate dataset/assessment-coverage counts. Original v1 is unchanged. Live tenant results remain dependent on sign-in, consent, licensing, scope and service retention.

# Microsoft 365 assessment v2 — 2.0.0-preview.3

See [Preview 3 setup and report guide](docs/REPAIR-PREVIEW3.md) for the Graph module prerequisite, redesigned dashboard, readable exports and progress/ETA behavior. The original toolkit is preserved.

# Microsoft 365 assessment toolkit — version 2 preview

Version **2.0.0-preview.2** adds optional evidence collectors in a self-contained `v2/` folder. The working scripts at the repository root remain unchanged from commit `dc684d38c8ab5f2b73f8a388178f6ef89826c72d`.

- [Preview.2 fixes and troubleshooting commands](docs/REPAIR-PREVIEW2.md)
- [Setup, exact switches, permissions and one-line commands](docs/SETUP-V2.md)
- [Changes and remaining evidence for all 20 original manual categories](docs/COVERAGE-V2.md)
- [Retained core permissions](docs/SETUP.md)

New collectors cover Fabric tenant settings/workspaces/accessible capacities, existing SharePoint and OneDrive DAG downloads, site reviews, licensed Copilot report v2, Copilot audit metadata, DLP/AI activity metadata, Teams policy definitions, Power Platform inventories, Endpoint recommendations, selected Dataverse bots, optional Graph beta agent registry, and a bounded selected-drive permissions scan. Evidence indexes and license-allocation calculations support human review.

New extensions are Commercial-only in this preview. GCC/GCC High launchers preserve original core routing and explicitly mark new capabilities unverified. Interactive and certificate launchers remain separate. Audit, Activity Explorer and Power Platform extensions are interactive-only in this preview; other app modes require documented workload permissions.

This does **not** turn all 20 categories into fully automated assessments. Native DSPM assessments, Compliance Manager, Insider Risk, full Security Copilot configuration, complete permissions/usage coverage and human approval decisions retain explicit evidence requirements. Read the coverage table before using outputs for customer conclusions.

New extension workloads run in isolated processes. The core collectors retain their working behavior. New API tokens stay in worker memory, pagination is bounded, incomplete data is retained, and workers never change tenant configuration. Only existing DAG reports are downloaded; report generation remains an administrator action.

Validation includes offline parser, pagination, truncation, metadata filtering, certificate-signature, CSV/HTML safety and run-provenance checks. Windows CI also runs the original regression suite and verifies original-file hashes. No live customer tenant was used during development. Treat this as a preview until a customer-authorized pilot confirms the selected workloads and permissions.

Run the new version using `v2/Commercial/Start-Interactive.ps1` or its certificate/GCC/GCC High counterpart. Default output is a separate `M365AssessmentV2` folder; examples use `ReportsV2`. To use the original version, run the repository-root launcher.
