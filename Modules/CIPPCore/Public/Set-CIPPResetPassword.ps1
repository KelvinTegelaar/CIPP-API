function Set-CIPPResetPassword {
    [CmdletBinding()]
    param(
        $UserID,
        $DisplayName,
        $TenantFilter,
        $APIName = 'Reset Password',
        $Headers,
        [bool]$forceChangePasswordNextSignIn = $true
    )

    try {
        $password = New-passwordString
        $passwordProfile = @{
            'passwordProfile' = @{
                'forceChangePasswordNextSignIn' = $forceChangePasswordNextSignIn
                'password'                      = $password
            }
        } | ConvertTo-Json -Compress

        $UserDetails = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserID)?`$select=onPremisesSyncEnabled" -noPagination $true -tenantid $TenantFilter -verbose
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserID)" -tenantid $TenantFilter -type PATCH -body $passwordProfile -verbose

        #PWPush
        $PasswordLink = $null
        try {
            $PasswordLink = New-PwPushLink -Payload $password
            if ($PasswordLink -and $PasswordLink -ne $false) {
                $password = $PasswordLink
            }
        }
        catch {
            Write-LogMessage -headers $Headers -API $APIName -message "Failed to create PwPush link, using plain password. Error: $($_.Exception.Message)" -sev 'Warn' -tenant $TenantFilter
        }
        Write-LogMessage -headers $Headers -API $APIName -message "Successfully reset the password for $DisplayName, $($UserID). User must change password is set to $forceChangePasswordNextSignIn" -Sev 'Info' -tenant $TenantFilter

        if ($UserDetails.onPremisesSyncEnabled -eq $true) {
            return [pscustomobject]@{
                resultText = "Successfully reset the password for $DisplayName, $($UserID). User must change password is set to $forceChangePasswordNextSignIn. The new password is $password. WARNING: This user is AD synced. Please confirm passthrough or writeback is enabled."
                copyField  = $password
                state      = 'warning'
            }
        } else {
            return [pscustomobject]@{
                resultText = "Successfully reset the password for $DisplayName, $($UserID). User must change password is set to $forceChangePasswordNextSignIn. The new password is $password"
                copyField  = $password
                state      = 'success'
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to reset password for $DisplayName, $($UserID). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Message
    }
}
