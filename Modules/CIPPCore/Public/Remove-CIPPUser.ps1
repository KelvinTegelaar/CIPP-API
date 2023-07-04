function Remove-CIPPUser {
    [CmdletBinding()]
    param (
        $ExecutingUser,
        $userid,
        $username,
        $APIName = "Remove User",
        $TenantFilter
    )

    try {
        $DeleteRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userid)" -type DELETE -tenant $TenantFilter
        Write-LogMessage -user $ExecutingUser, -API $APIName -message "Deleted account $username" -Sev "Info" -tenant $TenantFilter
        return "Deleted the user account $username"

    }
    catch {
        Write-LogMessage -user $ExecutingUser, -API $APIName -message "Could not delete $username" -Sev "Error" -tenant $TenantFilter
        return "Could not delete $username. Error: $($_.Exception.Message)"
    }
}

