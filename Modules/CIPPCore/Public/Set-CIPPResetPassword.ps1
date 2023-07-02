function Set-CIPPResetPassword {
    [CmdletBinding()]
    param(
        $userid,
        $tenantFilter,
        $ExecutingUser,
        [bool]$forceChangePasswordNextSignIn = $true
    )

    try { 
        $password = New-passwordString
        $passwordProfile = @{
            "passwordProfile" = @{
                "forceChangePasswordNextSignIn" = $forceChangePasswordNextSignIn
                "password"                      = $password
            }
        } | ConvertTo-Json -Compress

        $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$($userid)" -tenantid $TenantFilter -type PATCH -body $passwordProfile  -verbose

        Write-LogMessage -user $ExecutingUser -API "Reset Password" -message "Reset the password for $($userid)" -Sev "Info" -tenant $TenantFilter
        return "The new password is $password"
    }
    catch {
        Write-LogMessage -user $ExecutingUser -API "Reset Password" -message "Could not reset password for $($userid)" -Sev "Error" -tenant $TenantFilter
        return "Could not reset password for $($userid). Error: $($_.Exception.Message)"
    }
}
