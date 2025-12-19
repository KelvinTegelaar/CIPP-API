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

    .PARAMETER Reason
    Reason for JIT admin assignment. Defaults to 'No reason provided' as due to backwards compatibility this is not a mandatory field.

    .PARAMETER Headers
    Headers to include in logging

    .EXAMPLE
    Set-CIPPUserJITAdmin -TenantFilter 'contoso.onmicrosoft.com' -Headers@{UserPrincipalName = 'jit@contoso.onmicrosoft.com'} -Roles @('62e90394-69f5-4237-9190-012177145e10') -Action 'AddRoles' -Expiration (Get-Date).AddDays(1) -Reason 'Emergency access'

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [hashtable]$User,
        [string[]]$Roles,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Create', 'AddRoles', 'RemoveRoles', 'DeleteUser', 'DisableUser')]
        [string]$Action,
        [datetime]$Expiration,
        [datetime]$StartDate,
        [string]$Reason = 'No reason provided',
        $Headers,
        [string]$APIName = 'Set-CIPPUserJITAdmin'
    )

    if ($PSCmdlet.ShouldProcess("User: $($User.UserPrincipalName)", "Action: $Action")) {
        if ($Action -ne 'Create') {
            $UserObj = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/users/$($User.UserPrincipalName)" -tenantid $TenantFilter
        }

        switch ($Action) {
            'Create' {
                $Password = New-passwordString
                $Schema = Get-CIPPSchemaExtensions | Where-Object { $_.id -match '_cippUser' } | Select-Object -First 1

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
                    "$($Schema.id)"   = @{
                        jitAdminEnabled    = $false
                        jitAdminExpiration = $Expiration.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                        jitAdminStartDate  = if ($StartDate) { $StartDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
                        jitAdminReason     = $Reason
                        jitAdminCreatedBy  = if ($Headers) { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } else { 'Unknown' }
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
                    $LogData = @{
                        UserPrincipalName = $User.UserPrincipalName
                        Action            = 'Create'
                        Reason            = $Reason
                        StartDate         = if ($StartDate) { $StartDate.ToString('o') } else { (Get-Date).ToString('o') }
                        Expiration        = $Expiration.ToString('o')
                        ExpirationUTC     = $Expiration.ToUniversalTime().ToString('o')
                        CreatedBy         = if ($Headers) { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } else { 'Unknown' }
                    }
                    Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Created JIT Admin user: $($User.UserPrincipalName). Reason: $Reason" -Sev 'Info' -LogData $LogData
                    [PSCustomObject]@{
                        id                = $NewUser.id
                        userPrincipalName = $NewUser.userPrincipalName
                        password          = $Password
                    }
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-Information "Error creating user: $ErrorMessage"
                    throw $ErrorMessage
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
                $UserEnabled = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)?`$select=accountEnabled" -tenantid $TenantFilter).accountEnabled
                if (-not $UserEnabled) {
                    $Body = @{
                        accountEnabled = $true
                    }
                    $Json = ConvertTo-Json -Depth 5 -InputObject $Body
                    try {
                        New-GraphPOSTRequest -type PATCH -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $TenantFilter -body $Json | Out-Null
                    } catch {}
                }
                $CreatedBy = if ($Headers) {
                    ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
                } else { 'Unknown' }

                Set-CIPPUserJITAdminProperties -TenantFilter $TenantFilter -UserId $UserObj.id -Enabled -Expiration $Expiration -StartDate $StartDate -Reason $Reason -CreatedBy $CreatedBy | Out-Null
                $Message = "Added admin roles to user $($UserObj.displayName) ($($UserObj.userPrincipalName)). Reason: $Reason"
                $LogData = @{
                    UserPrincipalName = $UserObj.userPrincipalName
                    UserId            = $UserObj.id
                    DisplayName       = $UserObj.displayName
                    Action            = 'AddRoles'
                    Roles             = $Roles
                    Reason            = $Reason
                    StartDate         = if ($StartDate) { $StartDate.ToString('o') } else { (Get-Date).ToString('o') }
                    Expiration        = $Expiration.ToString('o')
                    ExpirationUTC     = $Expiration.ToUniversalTime().ToString('o')
                    CreatedBy         = if ($Headers) { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } else { 'Unknown' }
                }
                Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info' -LogData $LogData
                return "Added admin roles to user $($UserObj.displayName) ($($UserObj.userPrincipalName))"
            }
            'RemoveRoles' {
                $Roles = $Roles | ForEach-Object {
                    try {
                        $null = New-GraphPOSTRequest -type DELETE -uri "https://graph.microsoft.com/beta/directoryRoles(roleTemplateId='$($_)')/members/$($UserObj.id)/`$ref" -tenantid $TenantFilter
                    } catch {}
                }
                Set-CIPPUserJITAdminProperties -TenantFilter $TenantFilter -UserId $UserObj.id -Clear | Out-Null
                $Message = "Removed admin roles from user $($UserObj.displayName) ($($UserObj.userPrincipalName))"
                Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
                return "Removed admin roles from user $($UserObj.displayName)"
            }
            'DeleteUser' {
                try {
                    $null = New-GraphPOSTRequest -type DELETE -uri "https://graph.microsoft.com/beta/users/$($UserObj.userPrincipalName)" -tenantid $TenantFilter
                    $Message = "Deleted user $($UserObj.displayName) ($($UserObj.userPrincipalName)) with id $($UserObj.id)"
                    Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
                    return $Message
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Error deleting user $($UserObj.displayName) ($($UserObj.userPrincipalName)): $ErrorMessage" -Sev 'Error'
                    throw "Error deleting user $($UserObj.displayName) ($($UserObj.userPrincipalName)): $ErrorMessage"
                }
            }
            'DisableUser' {
                $Body = @{
                    accountEnabled = $false
                }
                $Json = ConvertTo-Json -Depth 5 -InputObject $Body -Compress
                try {
                    Write-Information "Disabling user $($UserObj.displayName) ($($User.UserPrincipalName))"
                    Write-Information $Json
                    Write-Information "https://graph.microsoft.com/beta/users/$($User.UserPrincipalName)"
                    $null = New-GraphPOSTRequest -type PATCH -uri "https://graph.microsoft.com/beta/users/$($User.UserPrincipalName)" -tenantid $TenantFilter -body $Json
                    Set-CIPPUserJITAdminProperties -TenantFilter $TenantFilter -UserId $User.UserPrincipalName -Clear | Out-Null
                    $Message = "Disabled user $($UserObj.displayName) ($($UserObj.userPrincipalName))"
                    Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
                    return $Message
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Error disabling user $($UserObj.displayName) ($($UserObj.userPrincipalName)): $ErrorMessage" -Sev 'Error'
                    throw "Error disabling user $($UserObj.displayName) ($($UserObj.userPrincipalName)): $ErrorMessage"
                }
            }
        }
    }
}
