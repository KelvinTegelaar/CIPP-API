function Revoke-CIPPSessions {
    [CmdletBinding()]
    param (
        $Headers,
        $UserID,
        $Username,
        $APIName = 'Revoke Sessions',
        $TenantFilter
    )

    try {
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserID)/invalidateAllRefreshTokens" -tenantid $TenantFilter -type POST -body '{}' -verbose
        $Result = "Successfully revoked sessions for $($Username)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info' -tenant $TenantFilter
        return $Result

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to revoke sessions for $($Username). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }
}
