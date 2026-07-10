function Set-CIPPDBCacheCsTeamsMessagingConfiguration {
    <#
    .SYNOPSIS
        Caches the Teams Messaging Configuration (Global)

    .DESCRIPTION
        Calls the Teams ConfigAPI (TeamsMessagingConfiguration) via New-TeamsRequestV2 and
        writes the result into the CippReportingDB under Type 'CsTeamsMessagingConfiguration'.
        Holds the org-wide message-safety settings (FileTypeCheck, UrlReputationCheck,
        ContentBasedPhishingCheck, ReportIncorrectSecurityDetections, etc.).

    .PARAMETER TenantFilter
        The tenant to cache the messaging configuration for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Teams Messaging Configuration' -sev Debug

        $MessagingConfig = New-TeamsRequestV2 -TenantFilter $TenantFilter -Type 'TeamsMessagingConfiguration' -Action Get -Identity 'Global'

        if ($MessagingConfig) {
            $Data = @($MessagingConfig)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CsTeamsMessagingConfiguration' -Data $Data -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Teams Messaging Configuration' -sev Debug
        }
        $MessagingConfig = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Teams Messaging Configuration: $($_.Exception.Message)" -sev Error
    }
}
