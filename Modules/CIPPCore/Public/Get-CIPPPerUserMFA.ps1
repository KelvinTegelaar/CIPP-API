function Get-CIPPPerUserMFA {
    [CmdletBinding()]
    param(
        $TenantFilter,
        $userId,
        $Headers,
        $AllUsers = $false
    )
    try {
        if ($AllUsers -eq $true) {
            $AllUsers = New-graphGetRequest -Uri "https://graph.microsoft.com/v1.0/users?`$top=999&`$select=UserPrincipalName,Id,perUserMfaState" -tenantid $tenantfilter
            return $AllUsers
        } else {
            $MFAState = New-graphGetRequest -Uri "https://graph.microsoft.com/v1.0/users/$($userId)?`$select=UserPrincipalName,Id,perUserMfaState" -tenantid $tenantfilter
            return [PSCustomObject]@{
                PerUserMFAState   = $MFAState.perUserMfaState
                UserPrincipalName = $userId
            }
        }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        "Failed to get MFA State for $id : $ErrorMessage"
    }
}
