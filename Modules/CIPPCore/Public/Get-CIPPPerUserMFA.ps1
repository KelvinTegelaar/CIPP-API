function Get-CIPPPerUserMFA {
    [CmdletBinding()]
    param(
        $TenantFilter,
        $userId,
        $executingUser
    )
    try {
        $MFAState = New-graphGetRequest -Uri "https://graph.microsoft.com/beta/users/$($userId)/authentication/requirements" -tenantid $tenantfilter
        return [PSCustomObject]@{
            user       = $userId
            PerUserMFA = $MFAState.perUserMfaState
        }
    } catch {
        "Failed to get MFA State for $id : $_"
    }
}