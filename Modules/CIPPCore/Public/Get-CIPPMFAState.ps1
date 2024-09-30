
function Get-CIPPMFAState {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $APIName = 'Get MFA Status',
        $ExecutingUser
    )
    $PerUserMFAState = Get-CIPPPerUserMFA -TenantFilter $TenantFilter -AllUsers $true
    $users = foreach ($user in (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users?$top=999&$select=id,UserPrincipalName,DisplayName,accountEnabled,assignedLicenses' -tenantid $TenantFilter)) {
        [PSCustomObject]@{
            UserPrincipalName = $user.UserPrincipalName
            isLicensed        = [boolean]$user.assignedLicenses.skuid
            accountEnabled    = $user.accountEnabled
            DisplayName       = $user.DisplayName
            ObjectId          = $user.id
        }
    }

    try {
        $SecureDefaultsState = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $TenantFilter ).IsEnabled
    } catch {
        Write-Host "Secure Defaults not available: $($_.Exception.Message)"
    }
    $CAState = [System.Collections.Generic.List[object]]::new()

    Try {
        $MFARegistration = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/reports/authenticationMethods/userRegistrationDetails' -tenantid $TenantFilter)
    } catch {
        $CAState.Add('Not Licensed for Conditional Access') | Out-Null
        $MFARegistration = $null
        Write-Host "User registration details not available: $($_.Exception.Message)"
    }

    if ($null -ne $MFARegistration) {
        $CASuccess = $true
        try {
            $CAPolicies = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' -tenantid $TenantFilter -ErrorAction Stop )
            foreach ($Policy in $CAPolicies) {
                $IsMFAControl = $policy.grantControls.builtincontrols -eq 'mfa' -or $Policy.grantControls.authenticationStrength.requirementsSatisfied -eq 'mfa' -or $Policy.grantControls.customAuthenticationFactors -eq 'RequireDuoMfa'
                $IsAllApps = [bool]($Policy.conditions.applications.includeApplications -eq 'All')
                $IsAllUsers = [bool]($Policy.conditions.users.includeUsers -eq 'All')
                $Platforms = $Policy.conditions.clientAppTypes

                if ($IsMFAControl) {
                    $CAState.Add([PSCustomObject]@{
                            DisplayName   = $Policy.displayName
                            State         = $Policy.state
                            IncludedApps  = $Policy.conditions.applications.includeApplications
                            IncludedUsers = $Policy.conditions.users.includeUsers
                            ExcludedUsers = $Policy.conditions.users.excludeUsers
                            IsAllApps     = $IsAllApps
                            IsAllUsers    = $IsAllUsers
                            Platforms     = $Platforms
                        })
                }
            }
        } catch {
            $CASuccess = $false
            $CAError = "CA policies not available: $($_.Exception.Message)"
        }
    }

    if ($CAState.count -eq 0) { $CAState.Add('None') | Out-Null }


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

        $PerUser = if ($PerUserMFAState -eq $null) { $null } else { ($PerUserMFAState | Where-Object -Property UserPrincipalName -EQ $_.UserPrincipalName).PerUserMFAState }

        $MFARegUser = if (($MFARegistration | Where-Object -Property UserPrincipalName -EQ $_.userPrincipalName).isMFARegistered -eq $null) { $false } else { ($MFARegistration | Where-Object -Property UserPrincipalName -EQ $_.userPrincipalName) }

        [PSCustomObject]@{
            Tenant          = $TenantFilter
            ID              = $_.ObjectId
            UPN             = $_.UserPrincipalName
            DisplayName     = $_.DisplayName
            AccountEnabled  = $_.accountEnabled
            PerUser         = $PerUser
            isLicensed      = $_.isLicensed
            MFARegistration = $MFARegUser.isMFARegistered
            MFACapable      = $MFARegUser.isMFACapable
            MFAMethods      = $MFARegUser.methodsRegistered
            CoveredByCA     = $CoveredByCA
            CAPolicies      = $UserCAState
            CoveredBySD     = $SecureDefaultsState
            RowKey          = [string]($_.UserPrincipalName).replace('#', '')
            PartitionKey    = 'users'
        }

    }
    return $GraphRequest
}
