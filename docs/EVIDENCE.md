# Importing customer evidence

This repository contains no customer report or tenant export. Keep all such material in an authorized local assessment folder.

1. Export the relevant portal report to CSV.
2. Name it using a Manual dataset ID from config/collectors.json, for example DSPMForAI.csv.
3. Create DSPMForAI.metadata.json beside it using this schema:
```json
{
  "TenantId": "<actual-tenant-guid>",
  "Cloud": "Commercial",
  "Source": "Microsoft Purview > DSPM for AI > exported report name",
  "CollectedAtUtc": "2026-09-17T16:00:00Z",
  "Scope": "Describe source reporting dates, population, filters and exclusions"
}
```
4. Run your entry point with -EvidencePath pointing to that folder.
5. Review collection-status.csv for Imported, Failed and ManualRequired entries.

Cloud must match Commercial, GCC or GCCHigh. Metadata with a different tenant/cloud is rejected. A CSV without metadata is not imported. Imported means supplied by the operator, not independently verified. Do not fabricate values to fill a template.

Screenshots and PDF pages are not parsed by this collector. Have an assessor transcribe relevant observations to a CSV with columns such as Control, ObservedValue, Scope, EvidenceReference, ValidationStatus and Recommendation; preserve the original screenshot outside the repository. Mark these as assessor observations in Source.

Blank or absent fields stay unknown. Do not treat blank dates as definitive inactivity when reporting suppression, identifier concealment or collection gaps may explain them. Do not mix registered agents with active agents or Entra enterprise applications. Do not compare prompt counts across unequal reporting periods.
