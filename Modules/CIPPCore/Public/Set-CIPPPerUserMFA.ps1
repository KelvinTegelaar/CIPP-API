function Set-CIPPPerUserMFA {
    [CmdletBinding()]
    param(
        $TenantFilter,
        $userId,
        [ValidateSet('enabled', 'disabled', 'enforced')]
        $State = 'enabled',
        $executingUser
    )
    try {
        $int = 0
        $Requests = foreach ($id in $userId) {
            @{
                id        = $int++
                method    = 'PATCH'
                url       = "users/$id/authentication/requirements"
                body      = @{ 'perUserMfaState' = "$state" }
                'headers' = @{
                    'Content-Type' = 'application/json'
                }
            }
        }
        $Requests = New-GraphBulkRequest -tenantid $tenantfilter -scope 'https://graph.microsoft.com/.default' -Requests @($Requests) -asapp $true
        "Successfully set Per user MFA State for $userId"
        Write-LogMessage -user $executingUser -API 'Set-CIPPPerUserMFA' -message "Successfully set Per user MFA State for $id" -Sev 'Info' -tenant $TenantFilter
    } catch {
        "Failed to set MFA State for $id : $_"
        Write-LogMessage -user $executingUser -API 'Set-CIPPPerUserMFA' -message "Failed to set MFA State for $id : $_" -Sev 'Error' -tenant $TenantFilter
    }
}