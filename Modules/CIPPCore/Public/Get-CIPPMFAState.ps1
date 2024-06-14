
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

    $SecureDefaultsState = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $TenantFilter ).IsEnabled
    $CAState = New-Object System.Collections.ArrayList

    Try {
        $MFARegistration = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails' -tenantid $TenantFilter)
    } catch {
        $CAState.Add('Not Licensed for Conditional Access') | Out-Null
        $MFARegistration = $null
    }

    if ($null -ne $MFARegistration) {
        $CAPolicies = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' -tenantid $TenantFilter -ErrorAction Stop )

        try {
            $ExcludeAllUsers = New-Object System.Collections.ArrayList
            $ExcludeSpecific = New-Object System.Collections.ArrayList

            foreach ($Policy in $CAPolicies) {
                if (($policy.grantControls.builtincontrols -eq 'mfa') -or ($policy.grantControls.authenticationStrength.requirementsSatisfied -eq 'mfa') -or ($policy.grantControls.customAuthenticationFactors -eq 'RequireDuoMfa')) {
                    if ($Policy.conditions.applications.includeApplications -ne 'All') {
                        Write-Host $Policy.conditions.applications.includeApplications
                        $CAState.Add("$($policy.displayName) - Specific Applications - $($policy.state)") | Out-Null
                        $Policy.conditions.users.excludeUsers.foreach({ $ExcludeSpecific.Add($_) | Out-Null })
                        continue
                    }
                    if ($Policy.conditions.users.includeUsers -eq 'All') {
                        $CAState.Add("$($policy.displayName) - All Users - $($policy.state)") | Out-Null
                        $Policy.conditions.users.excludeUsers.foreach({ $ExcludeAllUsers.Add($_) | Out-Null })
                        continue
                    }
                } 
            }
        } catch {
        }
    }

    if ($CAState.count -eq 0) { $CAState.Add('None') | Out-Null }


    # Interact with query parameters or the body of the request.
    $GraphRequest = $Users | ForEach-Object {
        Write-Host 'Processing users'
        $UserCAState = New-Object System.Collections.ArrayList
        foreach ($CA in $CAState) {
            if ($CA -like '*All Users*') {
                if ($ExcludeAllUsers -contains $_.ObjectId) { $UserCAState.Add("Excluded from $($policy.displayName) - All Users") | Out-Null }
                else { $UserCAState.Add($CA) | Out-Null }
            } elseif ($CA -like '*Specific Applications*') {
                if ($ExcludeSpecific -contains $_.ObjectId) { $UserCAState.Add("Excluded from $($policy.displayName) - Specific Applications") | Out-Null }
                else { $UserCAState.Add($CA) | Out-Null }
            } else {
                Write-Host 'Adding to CA'
                $UserCAState.Add($CA) | Out-Null
            }
        }

        $PerUser = if ($PerUserMFAState -eq $null) { $null } else { ($PerUserMFAState | Where-Object -Property UserPrincipalName -EQ $_.UserPrincipalName).PerUserMFAState }

        $MFARegUser = if (($MFARegistration | Where-Object -Property UserPrincipalName -EQ $_.UserPrincipalName).IsMFARegistered -eq $null) { $false } else { ($MFARegistration | Where-Object -Property UserPrincipalName -EQ $_.UserPrincipalName) }
        
        [PSCustomObject]@{
            Tenant          = $TenantFilter
            ID              = $_.ObjectId
            UPN             = $_.UserPrincipalName
            DisplayName     = $_.DisplayName
            AccountEnabled  = $_.accountEnabled
            PerUser         = $PerUser
            isLicensed      = $_.isLicensed
            MFARegistration = $MFARegUser.IsMFARegistered
            MFAMethods      = $($MFARegUser.authMethods -join ', ')
            CoveredByCA     = ($UserCAState -join ', ')
            CoveredBySD     = $SecureDefaultsState
            RowKey          = [string]($_.UserPrincipalName).replace('#', '')
            PartitionKey    = 'users'
        }
        
    }
    return $GraphRequest
}
