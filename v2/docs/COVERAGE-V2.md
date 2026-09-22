# Version 2 coverage review

Each of the 20 original manual categories is retained as a review boundary. Individual collectors have their own statuses. PartialCoverage never means a category passed.

| Original category | Automated datasets | Remaining review |
|---|---|---|
| CopilotChat | CopilotAuditActivity | Unlicensed Chat portal totals still need evidence; audit events cannot be classified by historical licensing from current license assignments. |
| CopilotOptimization | LicenseAllocationIndicators, CopilotLicensedUsageV2 | Review identity matching, reporting windows, manager decisions and portal recommendations. |
| CopilotPrompts | CopilotLicensedUsageV2 | Licensed report counts only; prompts content and populations outside this report are not collected. |
| DataAccessGovernance | DAGBothEveryone, DAGBothEveryoneExceptExternalUsers, DAGSharePointEveryoneExceptExternalUsersAtSite, DAGSharePointEveryoneExceptExternalUsersForItems, DAGSharePointPermissionedUsers, DAGSharePointPermissionsReport, DAGSharePointSensitivityLabelForFiles, DAGSharePointSharingLinks_Anyone, DAGSharePointSharingLinks_Guests, DAGSharePointSharingLinks_PeopleInYourOrg | Generate missing reports in the admin center and review downloaded artifacts against the desired sites and report dates. |
| AdvancedManagement | SharePointTenant, SharePointSites, SiteAccessReviews | Review remaining SAM lifecycle controls and remediation outcomes; these datasets do not represent every SAM feature. |
| OneDrivePermissions | DAGBothEveryone, DAGBothEveryoneExceptExternalUsers, DAGOneDriveForBusinessEveryoneExceptExternalUsersAtSite, DAGOneDriveForBusinessEveryoneExceptExternalUsersForItems, DAGOneDriveForBusinessPermissionedUsers, DAGOneDriveForBusinessPermissionsReport, DAGOneDriveForBusinessSharingLinks_Anyone, DAGOneDriveForBusinessSharingLinks_Guests, DAGOneDriveForBusinessSharingLinks_PeopleInYourOrg, ScopedItemPermissions | Review full ACL/inheritance and exposure outside selected drives and DAG scopes. |
| AuditEvidence | CopilotAuditActivity | Verify audit configuration, ingestion and retention separately; this is a CopilotInteraction search only. |
| DlpEffectiveness | DlpPolicies, DlpRules, DlpActivityMetadata | Controlled enforcement tests, policy scope and exclusions require human validation. |
| DSPMForAI | AIActivityMetadata, DlpActivityMetadata, SensitivityLabels | Native DSPM for AI recommendations/assessments are not reproduced; use dashboard evidence. |
| DSPM | DlpPolicies, SensitivityLabels, SharePointTenant | Configuration references only; native DSPM posture assessment remains unimplemented. |
| ComplianceManager | None in this version | Full Compliance Manager assessment export remains unimplemented; supply authorized evidence. |
| InsiderRisk | None in this version | Insider Risk configuration and analytics export remains unimplemented; supply authorized evidence. |
| DefenderConfiguration | EndpointRecommendations, DefenderAntiPhishPolicy, DefenderSafeLinksPolicy, DefenderSafeAttachmentPolicy | Other XDR workloads and enforcement outcomes need separate evidence; retained baseline collects all 15 MDO/EOP datasets. |
| SecurityCopilotConfiguration | None in this version | Full Security Copilot configuration export remains unimplemented; supply authorized evidence. |
| AgentInventory | AgentRegistryPreview, DataverseBots | Inventory covers registered agents and explicitly selected Dataverse environments only. |
| CopilotStudioSecurity | DataverseBots | Review connectors, knowledge sources, publication scope and effective access beyond returned bot fields. |
| PowerPlatformConfiguration | PowerPlatformEnvironments, PowerPlatformApps, PowerPlatformDlpPolicies, PowerPlatformTenantSettings, PowerPlatformFlows | Capacity, effective permissions, connector usage and additional environment controls need evidence. |
| FabricConfigurationUsage | FabricTenantSettings, FabricWorkspaces, FabricAccessibleCapacities | Item permissions, usage, overrides and capacities inaccessible to the caller need separate evidence. |
| TeamsPolicies | TeamsCsTeamsMeetingPolicy, TeamsCsTenantFederationConfiguration, TeamsCsTeamsClientConfiguration, TeamsCsTeamsGuestMessagingConfiguration, TeamsCsTeamsGuestMeetingConfiguration, TeamsCsTeamsAppSetupPolicy, TeamsCsTeamsAppPermissionPolicy | Effective assignments, app-centric controls and policy outcomes need separate evidence. |
| ExpansionGates | ExpansionEvidenceIndex | Business/control owners must approve each gate; evidence references are not approvals. |
