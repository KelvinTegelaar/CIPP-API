function Get-CIPPMFAState {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $APIName = 'Get MFA Status',
        $Headers
    )
    #$PerUserMFAState = Get-CIPPPerUserMFA -TenantFilter $TenantFilter -AllUsers $true
    $users = foreach ($user in (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/users?$top=999&$select=id,UserPrincipalName,DisplayName,accountEnabled,assignedLicenses,perUserMfaState' -tenantid $TenantFilter)) {
        [PSCustomObject]@{
            UserPrincipalName = $user.UserPrincipalName
            isLicensed        = [boolean]$user.assignedLicenses.Count
            accountEnabled    = $user.accountEnabled
            DisplayName       = $user.DisplayName
            ObjectId          = $user.id
            perUserMfaState   = $user.perUserMfaState
        }
    }

    $Errors = [System.Collections.Generic.List[object]]::new()
    try {
        $SecureDefaultsState = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $TenantFilter ).IsEnabled
    } catch {
        Write-Host "Secure Defaults not available: $($_.Exception.Message)"
        $Errors.Add(@{Step = 'SecureDefaults'; Message = $_.Exception.Message })
    }
    $CAState = [System.Collections.Generic.List[object]]::new()

    Try {
        $MFARegistration = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/authenticationMethods/userRegistrationDetails?$top=999&$select=userPrincipalName,isMfaRegistered,isMfaCapable,methodsRegistered" -tenantid $TenantFilter -asapp $true)
        $MFAIndex = @{}
        foreach ($MFAEntry in $MFARegistration) {
            $MFAIndex[$MFAEntry.userPrincipalName] = $MFAEntry
        }
    } catch {
        $CAState.Add('Not Licensed for Conditional Access') | Out-Null
        $MFARegistration = $null
        if ($_.Exception.Message -ne "Tenant is not a B2C tenant and doesn't have premium licenses") {
            $Errors.Add(@{Step = 'MFARegistration'; Message = $_.Exception.Message })
        }
        Write-Host "User registration details not available: $($_.Exception.Message)"
        $MFAIndex = @{}
    }

    if ($null -ne $MFARegistration) {
        $CASuccess = $true
        try {
            $CAPolicies = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies?$top=999&$filter=state eq 'enabled'&$select=id,displayName,state,grantControls,conditions' -tenantid $TenantFilter -ErrorAction Stop)
            $PolicyTable = @{}
            foreach ($Policy in $CAPolicies) {
                if ($Policy.conditions.users.includeUsers -ne $null) {
                    foreach ($UserId in $Policy.conditions.users.includeUsers) {
                        if (-not $PolicyTable.ContainsKey($UserId)) {
                            $PolicyTable[$UserId] = [System.Collections.Generic.List[object]]::new()
                        }
                        $PolicyTable[$UserId].Add($Policy)
                    }
                }
            }
        } catch {
            $CASuccess = $false
            $CAError = "CA policies not available: $($_.Exception.Message)"
            $Errors.Add(@{Step = 'CAPolicies'; Message = $_.Exception.Message })
        }
    }

    if ($CAState.count -eq 0) { $CAState.Add('None') | Out-Null }

    $assignments = New-GraphGetRequest -uri  "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$expand=principal" -tenantid $TenantFilter -ErrorAction SilentlyContinue

    $adminObjectIds = $assignments |
    Where-Object {
        $_.principal.'@odata.type' -eq '#microsoft.graph.user'
    } |
    ForEach-Object {
        $_.principal.id
    }

    # Interact with query parameters or the body of the request.
    $GraphRequest = $Users | ForEach-Object {
        $UserCAState = [System.Collections.Generic.List[object]]::new()
        foreach ($CA in $CAState) {
            if ($CA.IncludedUsers -eq 'All' -or $CA.IncludedUsers -contains $_.ObjectId) {
                $UserCAState.Add([PSCustomObject]@{
                        DisplayName  = $CA.DisplayName
                        UserIncluded = ($CA.ExcludedUsers -notcontains $_.ObjectId)
                        AllApps      = $CA.IsAllApps
                        PolicyState  = $CA.State
                        Platforms    = $CA.Platforms -join ', '
                    })
            }
        }
        if ($UserCAState.UserIncluded -eq $true -and $UserCAState.PolicyState -eq 'enabled') {
            if ($UserCAState.UserIncluded -eq $true -and $UserCAState.PolicyState -eq 'enabled' -and $UserCAState.AllApps) {
                $CoveredByCA = 'Enforced - All Apps'
            } else {
                $CoveredByCA = 'Enforced - Specific Apps'
            }
        } else {
            if ($CASuccess -eq $false) {
                $CoveredByCA = $CAError
            } else {
                $CoveredByCA = 'Not Enforced'
            }
        }
        $IsAdmin = if ($adminObjectIds -contains $_.ObjectId) { $true } else { $false }

        $PerUser = $_.PerUserMFAState

        $MFARegUser = if ($null -eq ($MFAIndex[$_.UserPrincipalName])) {
            $false
        } else {
            $MFAIndex[$_.UserPrincipalName]
        }

        [PSCustomObject]@{
            Tenant          = $TenantFilter
            ID              = $_.ObjectId
            UPN             = $_.UserPrincipalName
            DisplayName     = $_.DisplayName
            AccountEnabled  = $_.accountEnabled
            PerUser         = $PerUser
            isLicensed      = $_.isLicensed
            MFARegistration = if ($MFARegUser) { $MFARegUser.isMfaRegistered } else { $false }
            MFACapable      = if ($MFARegUser) { $MFARegUser.isMfaCapable } else { $false }
            MFAMethods      = if ($MFARegUser) { $MFARegUser.methodsRegistered } else { @() }
            CoveredByCA     = $CoveredByCA
            CAPolicies      = $UserCAState
            CoveredBySD     = $SecureDefaultsState
            IsAdmin         = $IsAdmin
            RowKey          = [string]($_.UserPrincipalName).replace('#', '')
            PartitionKey    = 'users'
        }
    }
    $ErrorCount = ($Errors | Measure-Object).Count
    if ($ErrorCount -gt 0) {
        if ($ErrorCount -gt 1) {
            $Text = 'errors'
        } else {
            $Text = 'an error'
        }
        Write-LogMessage -headers $Headers -API $APIName -Tenant $TenantFilter -message "The MFA report encountered $Text, see log data for details." -Sev 'Error' -LogData @($Errors.Message)
    }
    return $GraphRequest
}
