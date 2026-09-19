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
 [string]$OutputRoot = (Join-Path $env:LOCALAPPDATA 'M365Assessment'),
 [string]$EvidencePath,
 [switch]$IncludePurview,
 [switch]$IncludeSharePoint,
 [switch]$IncludeDefender,
 [switch]$DisableWAM
)
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
& (Join-Path $root 'src/Invoke-Assessment.ps1') @PSBoundParameters -Cloud 'GCCHigh' -Authentication 'Interactive'
