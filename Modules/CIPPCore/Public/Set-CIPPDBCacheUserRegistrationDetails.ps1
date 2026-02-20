function Set-CIPPDBCacheUserRegistrationDetails {
    <#
    .SYNOPSIS
        Caches authentication method registration details for all users in a tenant

    .PARAMETER TenantFilter
        The tenant to cache user registration details for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching user registration details' -sev Debug

        $UserRegistrationDetails = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/reports/authenticationMethods/userRegistrationDetails' -tenantid $TenantFilter

        if ($UserRegistrationDetails) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'UserRegistrationDetails' -Data $UserRegistrationDetails
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'UserRegistrationDetails' -Data $UserRegistrationDetails -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($UserRegistrationDetails.Count) user registration details" -sev Debug
        }
        $UserRegistrationDetails = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache user registration details: $($_.Exception.Message)" -sev Error
    }
}
