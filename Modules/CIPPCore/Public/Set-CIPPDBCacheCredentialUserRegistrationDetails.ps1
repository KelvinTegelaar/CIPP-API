function Set-CIPPDBCacheCredentialUserRegistrationDetails {
    <#
    .SYNOPSIS
        Caches MFA and SSPR registration details for all users in a tenant

    .PARAMETER TenantFilter
        The tenant to cache credential user registration details for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching credential user registration details' -sev Debug

        $CredentialUserRegistrationDetails = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails' -tenantid $TenantFilter

        if ($CredentialUserRegistrationDetails) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CredentialUserRegistrationDetails' -Data $CredentialUserRegistrationDetails
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CredentialUserRegistrationDetails' -Data $CredentialUserRegistrationDetails -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($CredentialUserRegistrationDetails.Count) credential user registration details" -sev Debug
        }
        $CredentialUserRegistrationDetails = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache credential user registration details: $($_.Exception.Message)" -sev Error
    }
}
