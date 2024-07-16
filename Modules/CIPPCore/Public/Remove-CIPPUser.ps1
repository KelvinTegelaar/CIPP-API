function Remove-CIPPUser {
    [CmdletBinding()]
    param (
        $ExecutingUser,
        $userid,
        $username,
        $APIName = 'Remove User',
        $TenantFilter
    )

    try {
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userid)" -type DELETE -tenant $TenantFilter
        Write-LogMessage -user $ExecutingUser, -API $APIName -message "Deleted account $username" -Sev 'Info' -tenant $TenantFilter
        return "Deleted the user account $username"

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $ExecutingUser, -API $APIName -message "Could not delete $username. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return "Could not delete $username. Error: $($ErrorMessage.NormalizedError)"
    }
}

