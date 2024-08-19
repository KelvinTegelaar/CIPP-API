
Function Set-CIPPAlwaysShowFrom {
    <#
    .SYNOPSIS
        Sets the "Always Show From" property for a user or all users in a tenant.

    .DESCRIPTION
        The Set-CIPPAlwaysShowFrom function is used to set the "Always Show From" property for a specified user or all users in a specified tenant. The "Always Show From" property determines whether the from field is always shown in Outlook.

    .PARAMETER UserID
        Specifies the user ID for which to set the "Always Show From" property. This can be UserPrincipalName, SamAccountName, GUID or Email address.
        This parameter is mandatory unless the RunOnAllUsersInTenant switch is used.

    .PARAMETER TenantFilter
        Specifies the tenant for which to set the "Always Show From" property. This parameter is mandatory.

    .PARAMETER APIName
        Specifies the name of the API. The default value is "Always Show From".

    .PARAMETER ExecutingUser
        Specifies the user who is executing the function.

    .PARAMETER AlwaysShowFrom
        Specifies whether to set the "Always Show From" property to true or false. This parameter is mandatory.

    .PARAMETER RunOnAllUsersInTenant
        If this switch is present, the function will set the "Always Show From" property for all users in the specified tenant.

    .EXAMPLE
        Set-CIPPAlwaysShowFrom -UserID "john.doe@example.com" -TenantFilter "example.com" -AlwaysShowFrom $true
        Sets the "Always Show From" property to true for the user "john.doe@example.com" in the "example.com" tenant.

    .EXAMPLE
        Set-CIPPAlwaysShowFrom -TenantFilter "example.com" -AlwaysShowFrom $true -RunOnAllUsersInTenant
        Sets the "Always Show From" property to true for all users in the "example.com" tenant.
    #>
    [CmdletBinding(DefaultParameterSetName = 'User')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'User')]
        [Parameter(Mandatory = $false, ParameterSetName = 'AllUsers')]
        [Alias('Username')][string]$UserID,

        [Parameter(Mandatory = $true, ParameterSetName = 'User')]
        [Parameter(Mandatory = $true, ParameterSetName = 'AllUsers')]
        $TenantFilter,

        [Parameter(ParameterSetName = 'User')]
        [Parameter(ParameterSetName = 'AllUsers')]
        $APIName = 'Always Show From',

        [Parameter(ParameterSetName = 'User')]
        [Parameter(ParameterSetName = 'AllUsers')]
        $ExecutingUser,

        [Parameter(Mandatory = $true, ParameterSetName = 'User')]
        [Parameter(Mandatory = $true, ParameterSetName = 'AllUsers')]
        [bool]$AlwaysShowFrom,

        [Parameter(ParameterSetName = 'AllUsers')]
        [switch]$RunOnAllUsersInTenant
    )


    if ($RunOnAllUsersInTenant.IsPresent -eq $true) {
        $AllUsers = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{ ResultSize = 'Unlimited' }
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Setting Always Show From to $AlwaysShowFrom for all $($AllUsers.Count) users in $TenantFilter" -Sev 'Info' -tenant $TenantFilter
        $ErrorCount = 0
        foreach ($User in $AllUsers) {
            try {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxMessageConfiguration' -anchor $User.UserPrincipalName -cmdParams @{AlwaysShowFrom = $AlwaysShowFrom; Identity = $User.UserPrincipalName }
                # Write-Information "Set Always Show From to $AlwaysShowFrom for $($User.UserPrincipalName)"
            } catch {
                $ErrorCount++
            }
        }
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Set Always Show From to $AlwaysShowFrom for $($AllUsers.Count - $ErrorCount) users in $TenantFilter" -Sev 'Info' -tenant $TenantFilter
        return "Set Always Show From to $AlwaysShowFrom for $($AllUsers.Count - $ErrorCount) users in $TenantFilter"
    } else {
        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxMessageConfiguration' -anchor $UserID -cmdParams @{AlwaysShowFrom = $AlwaysShowFrom; Identity = $UserID }
            Write-LogMessage -user $ExecutingUser -API $APIName -message "Set Always Show From to $AlwaysShowFrom for $UserID" -Sev 'Info' -tenant $TenantFilter
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not set Always Show From to $AlwaysShowFrom for $UserID. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
            return "Could not set Always Show From to $AlwaysShowFrom for $UserID. Error: $($ErrorMessage.NormalizedError)"
        }
        return "Set Always Show From to $AlwaysShowFrom for $UserID"
    }
}
