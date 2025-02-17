function Remove-CIPPUser {
    [CmdletBinding()]
    param (
        $Headers,
        $userid,
        $username,
        $APIName = 'Remove User',
        $TenantFilter
    )

    try {
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userid)" -type DELETE -tenant $TenantFilter
        Write-LogMessage -headers $Headers -API $APIName -message "Deleted account $username" -Sev 'Info' -tenant $TenantFilter
        return "Deleted the user account $username"

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Could not delete $username. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return $Message
    }
}

