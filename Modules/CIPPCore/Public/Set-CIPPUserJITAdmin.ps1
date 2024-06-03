function Set-CIPPUserJITAdmin {
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param(
        [string]$TenantFilter,
        $User,
        [string[]]$Roles,
        [string]$Action,
        $Expiration
    )

    if ($PSCmdlet.ShouldProcess("User: $($User.UserPrincipalName)", "Action: $Action")) {
        if ($Action -ne 'Create') {
            $UserObj = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/users/$($User.UserPrincipalName)" -tenantid $TenantFilter
        }

        switch ($Action) {
            'Create' {
                $Schema = Get-CIPPSchemaExtensions | Where-Object { $_.id -match '_cippUser' }
                $Body = @{
                    accountEnabled    = $true
                    displayName       = $User.FirstName + ' ' + $User.LastName
                    userPrincipalName = $User.UserPrincipalName
                    passwordProfile   = @{
                        forceChangePasswordNextSignIn = $true
                        password                      = New-passwordString
                    }
                    "$($Schema.id)"   = @{
                        jitAdminEnabled    = $false
                        jitAdminExpiration = $Expiration.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                    }
                }
                $Json = ConvertTo-Json -Depth 5 -InputObject $Body
                $NewUser = New-GraphPOSTRequest -Uri 'https://graph.microsoft.com/beta/users' -Body $Json -tenantid $TenantFilter
                [PSCustomObject]@{
                    id                = $NewUser.id
                    userPrincipalName = $NewUser.userPrincipalName
                    password          = $Body.passwordProfile.password
                }
            }
            'AddRoles' {
                $Roles = $Roles | ForEach-Object {
                    try {
                        $Body = @{
                            '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($UserObj.id)"
                        }
                        $Json = ConvertTo-Json -Depth 5 -InputObject $Body
                        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/directoryRoles(roleTemplateId='$($_)')/members/`$ref" -tenantid $TenantFilter -body $Json
                    } finally {}
                    Set-CIPPUserJITAdminProperties -TenantFilter $TenantFilter -UserId $UserObj.id -Enabled -Expiration $Expiration
                    return "Added admin roles to user $($UserObj.displayName) ($($UserObj.userPrincipalName))"
                }
            }
            'RemoveRoles' {
                $Roles = $Roles | ForEach-Object {
                    try {
                        $null = New-GraphPOSTRequest -type DELETE -uri "https://graph.microsoft.com/beta/directoryRoles(roleTemplateId='$($_)')/members/$($UserObj.id)/`$ref" -tenantid $TenantFilter
                    } finally {}
                }
                Set-CIPPUserJITAdminProperties -TenantFilter $TenantFilter -UserId $UserObj.id -Clear
                return "Removed admin roles from user $($UserObj.displayName)"
            }
            'DeleteUser' {
                $null = New-GraphPOSTRequest -type DELETE -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $TenantFilter
                return "Deleted user $($UserObj.displayName) ($($UserObj.userPrincipalName)) with id $($UserObj.id)"
            }
            'DisableUser' {
                $Body = @{
                    accountEnabled = $false
                }
                $Json = ConvertTo-Json -Depth 5 -InputObject $Body
                New-GraphPOSTRequest -type PATCH -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $TenantFilter -body $Json
                Set-CIPPUserJITAdminProperties -TenantFilter $TenantFilter -UserId $UserObj.id -Enabled:$false
                return "Disabled user $($UserObj.displayName) ($($UserObj.userPrincipalName))"
            }
        }
    }
}