function Set-CIPPSignInState {
    [CmdletBinding()]
    param (
        $userid,
        [bool]$AccountEnabled,
        $TenantFilter,
        $ExecutingUser
    )

    try {
        $body = @{
            accountEnabled = [bool]$AccountEnabled
        } | ConvertTo-Json -Compress -Depth 1
        $SignInState = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$($userid)" -tenantid $TenantFilter -type PATCH -body $body -verbose
        Write-LogMessage -user $ExecutingUser -API "Disable User Sign-in"  -message "Disabled $($userid)" -Sev "Info"  -tenant $TenantFilter
        return "Disabled user account for $userid"
    }
    catch {
        Write-LogMessage -user $ExecutingUser -API "Disable User Sign-in"  -message "Could not disable sign in for $($userid)" -Sev "Error" -tenant $TenantFilter
        return "Could not disable $($userid). Error: $($_.Exception.Message)"
    }
}
