function Set-CIPPDBCacheCopilotReadinessActivity {
    <#
    .SYNOPSIS
        Caches Microsoft 365 Copilot readiness activity per user for a tenant

    .DESCRIPTION
        Calls the reports.office.com OData endpoint which returns per-user booleans
        for each readiness signal (update channel, Teams meetings, Teams chat, Outlook
        email, Office docs) across multiple report periods (7, 30, 90, 180 days).
        Data is flattened to the 30-day period for storage.

    .PARAMETER TenantFilter
        The tenant to cache Copilot readiness activity for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Copilot readiness activity' -sev Debug

        $TenantId = (Get-Tenants -TenantFilter $TenantFilter).customerId
        $ReadinessData = New-GraphGetRequest -uri "https://reports.office.com/odataux/getCopilotReadinessActivityUserDetail?tenantId=$TenantId" -tenantid $TenantFilter -scope 'https://reports.office.com/.default'

        # Flatten to one row per user using the 30-day period window, matching the MS admin report view
        $FlattenedData = foreach ($User in $ReadinessData) {
            $Period30 = $User.copilotReadinessActivityUserDetailsByPeriod | Where-Object { $_.reportPeriod -eq 30 }
            if ($Period30) {
                [pscustomobject]@{
                    userPrincipalName         = $User.userPrincipalName
                    hasCopilotLicenseAssigned = [bool]$User.hasCopilotLicenseAssigned
                    onQualifiedUpdateChannel  = [bool]$Period30.onQualifiedUpdateChannel
                    usesTeamsMeetings         = [bool]$Period30.usesTeamsMeetings
                    usesTeamsChat             = [bool]$Period30.usesTeamsChat
                    usesOutlookEmail          = [bool]$Period30.usesOutlookEmail
                    usesOfficeDocs            = [bool]$Period30.usesOfficeDocs
                }
            }
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CopilotReadinessActivity' -Data $FlattenedData
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CopilotReadinessActivity' -Data $FlattenedData -Count
        $FlattenedData = $null
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Copilot readiness activity successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Copilot readiness activity: $($_.Exception.Message)" -sev Error
    }
}
