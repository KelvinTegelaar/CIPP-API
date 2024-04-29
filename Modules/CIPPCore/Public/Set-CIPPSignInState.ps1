function Set-CIPPSignInState {
    [CmdletBinding()]
    param (
        $userid,
        [bool]$AccountEnabled,
        $TenantFilter,
        $APIName = 'Disable User Sign-in',
        $ExecutingUser
    )

    try {
        $body = @{
            accountEnabled = [bool]$AccountEnabled
        } | ConvertTo-Json -Compress -Depth 1
        $SignInState = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$($userid)" -tenantid $TenantFilter -type PATCH -body $body -verbose
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Set account enabled state to $AccountEnabled for $userid" -Sev 'Info' -tenant $TenantFilter
        return "Set account enabled state to $AccountEnabled for $userid"
    } catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not disable sign in for $userid. Error: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter
        return "Could not disable $userid. Error: $($_.Exception.Message)"
    }
}

