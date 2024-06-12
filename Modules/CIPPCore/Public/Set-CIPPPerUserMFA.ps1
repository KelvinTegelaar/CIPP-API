function Set-CIPPPerUserMFA {
    [CmdletBinding()]
    param(
        $TenantFilter,
        $userId,
        [ValidateSet('enabled', 'disabled', 'enforced')]
        $State = 'users',
        $executingUser
    )
    try {
        $state = @{ 'perUserMfaState' = "$state" } | ConvertTo-Json
        New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/users/$userId/authentication/requirements" -tenantid $tenantfilter -type PUT -body $state -ContentType $ContentType
        "Successfully set Per user MFA State for $id"
        Write-LogMessage -user $executingUser -API 'Set-CIPPPerUserMFA' -message "Successfully set Per user MFA State for $id" -Sev 'Info' -tenant $TenantFilter
    } catch {
        "Failed to set MFA State for $id : $_"
        Write-LogMessage -user $executingUser -API 'Set-CIPPPerUserMFA' -message "Failed to set MFA State for $id : $_" -Sev 'Error' -tenant $TenantFilter
    }
}