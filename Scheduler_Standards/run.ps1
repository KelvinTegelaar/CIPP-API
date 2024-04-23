using namespace System.Net

param($Timer)
Write-LogMessage -API 'Standards' -message 'Starting Standards Schedule' -sev Info
Invoke-CIPPStandardsRun -tenantfilter 'allTenants'
Write-LogMessage -API 'Standards' -message 'Launched all standard jobs' -sev Info