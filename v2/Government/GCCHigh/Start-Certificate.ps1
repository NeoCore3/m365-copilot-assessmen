#requires -Version 7.4
[CmdletBinding()]
param(
 [Parameter(Mandatory)][guid]$TenantId,
 [Parameter(Mandatory)][string]$CustomerName,
 [string]$ClientId,
 [string]$CertificateThumbprint,
 [string]$Organization,
 [string]$AdminUPN,
 [string]$SharePointAdminUrl,
 [ValidateSet('D7','D30','D90','D180')][string]$Period = 'D90',
 [string]$OutputRoot = (Join-Path $env:LOCALAPPDATA 'M365AssessmentV2'),
 [string]$EvidencePath,
 [switch]$IncludePurview,
 [switch]$IncludeSharePoint,
 [switch]$IncludeDefender,
 [switch]$IncludeFabric, [switch]$IncludeDAG, [switch]$IncludeTeamsPolicies,
 [switch]$IncludePowerPlatform, [switch]$IncludeAudit, [switch]$IncludeActivityExplorer,
 [switch]$IncludeAgents, [switch]$IncludeAgentRegistryPreview, [switch]$IncludeEndpoint,
 [switch]$IncludeItemPermissions,
 [string]$ApiClientId, [string[]]$DataverseUrls, [string[]]$DriveIds,
 [ValidateRange(1,10000)][int]$MaxPages=200,
 [ValidateRange(1,1000000)][int]$MaxRows=100000,
 [ValidateRange(1,100000)][int]$MaxItems=1000,
 [switch]$ExtensionsOnly,
 [switch]$DisableWAM
)
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
& (Join-Path $root 'src/Invoke-Assessment.ps1') @PSBoundParameters -Cloud 'GCCHigh' -Authentication 'Certificate'
