# Evidence coverage

Automated configuration uses Graph and optional workload PowerShell. Imported evidence extends the report without implying unsupported automation. Review each dataset's collection status.

| Workstream | Dataset | Method | Explanation |
|---|---|---|---|
| Licensing | Organization | Graph | Tenant identity and organization settings. |
| Licensing | Licenses | Graph | Subscription SKU and service-plan inventory; consumed units describe assignment, not usage. |
| Licensing | UserAssignments | Graph | Per-user licenses, plan states and assignment provenance. Do not infer inactivity from assignment. |
| Identity | ConditionalAccess | Graph | Review policy state, inclusions, exclusions and grants. Existence alone does not prove effective coverage. |
| Identity | SecurityDefaults | Graph | Security defaults configuration; correlate with Conditional Access. |
| Agents | ServicePrincipals | Graph | Entra enterprise application inventory only. This is not a complete agent inventory and must not be counted as agents. |
| Defender | SecureScores | Graph | Latest Secure Score snapshot; not a complete Defender configuration assessment. |
| Defender | SecureScoreControls | Graph | Microsoft control descriptions and remediation guidance. Correlate control IDs with scores. |
| SharePoint | GraphSharePointSettings | Graph | Graph tenant sharing and security settings; supplement with SPO tenant and site exports. |
| Teams | TeamsUsage | Graph usage report | Usage report for the selected window. Retain source refresh date; concealed identifiers cannot be reliably joined to user assignments. |
| SharePoint | SharePointUsage | Graph usage report | Usage report for the selected window. Retain source refresh date; concealed identifiers cannot be reliably joined to user assignments. |
| OneDrive | OneDriveUsage | Graph usage report | Usage report for the selected window. Retain source refresh date; concealed identifiers cannot be reliably joined to user assignments. |
| Licensing | M365ActiveUsers | Graph usage report | Usage report for the selected window. Retain source refresh date; concealed identifiers cannot be reliably joined to user assignments. |
| Copilot | CopilotLicensedUsage | Graph usage report | Licensed Microsoft 365 Copilot activity, report v1. This does not include unlicensed Chat usage or prompt counts. GCC High API is not supported. |
| Copilot | CopilotChat | Portal CSV import | Export unlicensed Chat usage, refresh date, period, active users and prompts. Do not merge with licensed usage without validated identities and matching windows. |
| Copilot | CopilotOptimization | Portal CSV import | Capture configuration and optimization recommendations, web grounding controls, agents, connectors and rollout scope. |
| Copilot | CopilotPrompts | Portal CSV import | Export prompt and active-day metrics with the exact reporting window; the automated v1 report is activity-date based. |
| SharePoint | DataAccessGovernance | Portal CSV import | Export EEEU, sharing links, permissions and sensitivity reports. Preserve report scope, generated date and denominator; configuration inventory is not an ACL scan. |
| SharePoint | AdvancedManagement | Portal CSV import | Export lifecycle policies, inactive sites, ownership, restricted access/content discovery and site access review evidence. |
| OneDrive | OneDrivePermissions | Portal CSV import | Export unique permissions, external access, broad grants and sharing links. Broken inheritance does not by itself prove oversharing. |
| Purview | AuditEvidence | Portal CSV import | Confirm audit ingestion, licensing, retention and sample Copilot events; configuration alone does not verify event ingestion. |
| Purview | DlpEffectiveness | Portal CSV import | Export policy scope, simulation/enforcement and sensitive interaction outcomes. A zero blocked count does not independently prove policy failure. |
| Purview | DSPMForAI | Portal CSV import | Export settings, sensitive AI interactions, policy coverage, recommendations and assessed population. |
| Purview | DSPM | Portal CSV import | Export posture, recommendations, assessments and coverage denominators. |
| Purview | ComplianceManager | Portal CSV import | Export assessments, improvement actions, score and ownership; document scoring scope. |
| Purview | InsiderRisk | Portal CSV import | Export policy scope and analytics status through an authorized reviewer; exclude case content and personal investigation details. |
| Defender | DefenderConfiguration | Portal CSV import | Export workload settings, recommendations, exposure management and security posture. Secure Score is only a subset. |
| SecurityCopilot | SecurityCopilotConfiguration | Portal CSV import | Capture capacity, roles, plugins, connections, data access, audit and enabled integrations. |
| Agents | AgentInventory | Portal CSV import | Export actual agents, owners, publishers, activity, permissions, connectors, knowledge sources and review status. |
| CopilotStudio | CopilotStudioSecurity | Portal CSV import | Export authentication, publication, channel scope, environment access, connector policies and agent analytics. |
| PowerPlatform | PowerPlatformConfiguration | Portal CSV import | Export tenant settings, environments, apps, flows, DLP policies, connectors, capacity, security groups and usage. |
| Fabric | FabricConfigurationUsage | Portal CSV import | Export tenant settings, capacities, workspaces, sharing, Copilot enablement, security and usage. Preserve capacity/workspace scope. |
| Teams | TeamsPolicies | Portal CSV import | Export app permission/setup policies, meeting policies, transcription, recording, external/federation and guest settings. |
| Governance | ExpansionGates | Portal CSV import | Document governance board, acceptable use, owners, license optimization, security tests, rollout cohorts and measurable gates. |

Optional Purview collection adds labels, publishing policies, DLP policies/rules, retention policies/rules/labels and auto-label policies/rules. Optional SPO collection adds tenant settings, site settings and OneDrive site settings. Neither enumerates item ACLs. Coverage status is not a control maturity score.

## Assessment interpretation

The customer-facing reference documents were consulted for evidence principles and assessment scope; their individual tenant values and readiness judgments are not embedded in this toolkit. The implementation preserves missing-evidence distinctions, source dates, licensing/usage boundaries and expansion gates. This is not a reproduction or full automated extraction of every reference-document finding.

## Defender for Office 365 configuration

`-IncludeDefender` additionally collects 15 Exchange Online datasets: anti-phishing, Safe Links, Safe Attachments, inbound spam, outbound spam and anti-malware policies **and their rules**, plus `Get-AtpPolicyForO365`, `Get-ATPProtectionPolicyRule` and `Get-EOPProtectionPolicyRule`. Policy assignments, exclusions, priorities and preset-policy rules must be reviewed together. These commands run independently of Graph and Purview; each command has its own collection status.

`DefenderConfiguration` remains supplemental manual evidence for areas these commands do not cover, including Defender for Endpoint, Defender for Identity, Defender for Cloud Apps, exposure management and incidents. No full Defender or Purview portal extraction is claimed. Licensing and cloud availability can limit individual commands.
