function Set-CIPPRequirePasswordChange {
    <#
    .SYNOPSIS
        Require (or clear) password change at next sign-in without resetting the password.
    .DESCRIPTION
        Sets passwordProfile.forceChangePasswordNextSignIn via Graph. Directory-synced users
        are rejected: that flag is not managed for on-premises password authority.
    #>
    [CmdletBinding()]
    param(
        $UserID,
        $TenantFilter,
        $APIName = 'Require Password Change',
        $Headers,
        [bool]$ForceChangePasswordNextSignIn = $true
    )

    try {
        $UserDetails = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserID)?`$select=onPremisesSyncEnabled,displayName,userPrincipalName" -noPagination $true -tenantid $TenantFilter -verbose
        $Label = $UserDetails.userPrincipalName ?? $UserDetails.displayName ?? $UserID

        if ($UserDetails.onPremisesSyncEnabled -eq $true) {
            $Message = "Cannot set must-change-password for $Label. This user is directory synced; manage password change requirements in on-premises Active Directory."
            Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter
            throw $Message
        }

        $passwordProfile = @{
            passwordProfile = @{
                forceChangePasswordNextSignIn = $ForceChangePasswordNextSignIn
            }
        } | ConvertTo-Json -Compress

        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserID)" -tenantid $TenantFilter -type PATCH -body $passwordProfile -verbose

        $StateText = if ($ForceChangePasswordNextSignIn) { 'required' } else { 'not required' }
        $Result = "Successfully set password change at next logon to $StateText for $Label"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info' -tenant $TenantFilter
        return $Result
    } catch {
        if ($_.Exception.Message -like 'Cannot set must-change-password*') {
            throw
        }
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to set password change at next logon for $UserID. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Message
    }
}
