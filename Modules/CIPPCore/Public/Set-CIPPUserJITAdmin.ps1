function Set-CIPPUserJITAdmin {
    <#
    .SYNOPSIS
    Just-in-time admin management

    .DESCRIPTION
    Just-in-time admin management for CIPP. This function can create users, add roles, remove roles, delete, or disable a user.

    .PARAMETER TenantFilter
    Tenant to manage for JIT admin

    .PARAMETER User
    User object to manage JIT admin roles, required property UserPrincipalName - If user is being created we also require FirstName and LastName

    .PARAMETER Roles
    List of Role GUIDs to add or remove

    .PARAMETER Action
    Action to perform: Create, AddRoles, RemoveRoles, DeleteUser, DisableUser

    .PARAMETER Expiration
    DateTime for expiration

    .EXAMPLE
    Set-CIPPUserJITAdmin -TenantFilter 'contoso.onmicrosoft.com' -User @{UserPrincipalName = 'jit@contoso.onmicrosoft.com'} -Roles @('62e90394-69f5-4237-9190-012177145e10') -Action 'AddRoles' -Expiration (Get-Date).AddDays(1)

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [hashtable]$User,

        [string[]]$Roles,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Create', 'AddRoles', 'RemoveRoles', 'DeleteUser', 'DisableUser')]
        [string]$Action,

        [datetime]$Expiration
    )

    if ($PSCmdlet.ShouldProcess("User: $($User.UserPrincipalName)", "Action: $Action")) {
        if ($Action -ne 'Create') {
            $UserObj = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/users/$($User.UserPrincipalName)" -tenantid $TenantFilter
        }

        switch ($Action) {
            'Create' {
                $Password = New-passwordString
                $Body = @{
                    givenName         = $User.FirstName
                    surname           = $User.LastName
                    accountEnabled    = $true
                    displayName       = $User.FirstName + ' ' + $User.LastName
                    userPrincipalName = $User.UserPrincipalName
                    mailNickname      = $User.UserPrincipalName.Split('@')[0]
                    passwordProfile   = @{
                        forceChangePasswordNextSignIn        = $true
                        forceChangePasswordNextSignInWithMfa = $false
                        password                             = $Password
                    }
                }
                $Json = ConvertTo-Json -Depth 5 -InputObject $Body
                try {
                    $NewUser = New-GraphPOSTRequest -type POST -Uri 'https://graph.microsoft.com/beta/users' -Body $Json -tenantid $TenantFilter
                    #PWPush
                    $PasswordLink = New-PwPushLink -Payload $Password
                    if ($PasswordLink) {
                        $Password = $PasswordLink
                    }
                    [PSCustomObject]@{
                        id                = $NewUser.id
                        userPrincipalName = $NewUser.userPrincipalName
                        password          = $Password
                    }
                } catch {
                    Write-Information "Error creating user: $($_.Exception.Message)"
                    throw $_.Exception.Message
                }
            }
            'AddRoles' {
                $Roles = $Roles | ForEach-Object {
                    try {
                        $Body = @{
                            '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($UserObj.id)"
                        }
                        $Json = ConvertTo-Json -Depth 5 -InputObject $Body
                        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/directoryRoles(roleTemplateId='$($_)')/members/`$ref" -tenantid $TenantFilter -body $Json -ErrorAction SilentlyContinue
                    } catch {}
                }
                Set-CIPPUserJITAdminProperties -TenantFilter $TenantFilter -UserId $UserObj.id -Enabled -Expiration $Expiration | Out-Null
                return "Added admin roles to user $($UserObj.displayName) ($($UserObj.userPrincipalName))"
            }
            'RemoveRoles' {
                $Roles = $Roles | ForEach-Object {
                    try {
                        $null = New-GraphPOSTRequest -type DELETE -uri "https://graph.microsoft.com/beta/directoryRoles(roleTemplateId='$($_)')/members/$($UserObj.id)/`$ref" -tenantid $TenantFilter
                    } catch {}
                }
                Set-CIPPUserJITAdminProperties -TenantFilter $TenantFilter -UserId $UserObj.id -Clear | Out-Null
                return "Removed admin roles from user $($UserObj.displayName)"
            }
            'DeleteUser' {
                try {
                    $null = New-GraphPOSTRequest -type DELETE -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $TenantFilter
                    return "Deleted user $($UserObj.displayName) ($($UserObj.userPrincipalName)) with id $($UserObj.id)"
                } catch {
                    return "Error deleting user $($UserObj.displayName) ($($UserObj.userPrincipalName)): $($_.Exception.Message)"
                }
            }
            'DisableUser' {
                $Body = @{
                    accountEnabled = $false
                }
                $Json = ConvertTo-Json -Depth 5 -InputObject $Body
                try {
                    New-GraphPOSTRequest -type PATCH -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $TenantFilter -body $Json
                    Set-CIPPUserJITAdminProperties -TenantFilter $TenantFilter -UserId $UserObj.id -Enabled:$false | Out-Null
                    return "Disabled user $($UserObj.displayName) ($($UserObj.userPrincipalName))"
                } catch {
                    return "Error disabling user $($UserObj.displayName) ($($UserObj.userPrincipalName)): $($_.Exception.Message)"
                }
            }
        }
    }
}