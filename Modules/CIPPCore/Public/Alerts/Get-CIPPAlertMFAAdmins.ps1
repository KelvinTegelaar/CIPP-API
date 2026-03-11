function Get-CIPPAlertMFAAdmins {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    try {
        $CAPolicies = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?$top=999' -tenantid $TenantFilter -ErrorAction Stop)
        foreach ($Policy in $CAPolicies) {
            if ($policy.grantControls.customAuthenticationFactors -eq 'RequireDuoMfa') {
                $DuoActive = $true
            }
        }
        if (!$DuoActive) {
            $MFAReport = try { Get-CIPPMFAStateReport -TenantFilter $TenantFilter | Where-Object { $_.DisplayName -ne 'On-Premises Directory Synchronization Service Account' } } catch { $null }
            $IncludeDisabled = [System.Convert]::ToBoolean($InputValue)

            # Check 1: Admins with no MFA registered — prefer cache, fall back to live Graph
            $Users = if ($MFAReport) {
                $MFAReport | Where-Object { $_.IsAdmin -eq $true -and $_.MFARegistration -eq $false -and ($IncludeDisabled -or $_.AccountEnabled -eq $true) }
            } else {
                New-GraphGETRequest -uri "https://graph.microsoft.com/beta/reports/authenticationMethods/userRegistrationDetails?`$top=999&filter=IsAdmin eq true and isMfaRegistered eq false and userType eq 'member'&`$select=id,userDisplayName,userPrincipalName,lastUpdatedDateTime,isMfaRegistered,IsAdmin" -tenantid $($TenantFilter) -AsApp $true |
                    Where-Object { $_.userDisplayName -ne 'On-Premises Directory Synchronization Service Account' } |
                    Select-Object @{n = 'ID'; e = { $_.id } }, @{n = 'UPN'; e = { $_.userPrincipalName } }, @{n = 'DisplayName'; e = { $_.userDisplayName } }
            }

            # Check 2: Admins with MFA registered but no enforcement.
            # I hate how this ended up looking, but I couldn't think of a better way to do it ¯\_(ツ)_/¯
            $UnenforcedAdmins = $MFAReport | Where-Object {
                $_.IsAdmin -eq $true -and
                $_.MFARegistration -eq $true -and
                ($IncludeDisabled -or $_.AccountEnabled -eq $true) -and
                $_.PerUser -notin @('Enforced', 'Enabled') -and
                $null -ne $_.CoveredBySD -and
                $_.CoveredBySD -ne $true -and
                $_.CoveredByCA -notlike 'Enforced*'
            }

            # Filter out JIT admins
            if ($Users -or $UnenforcedAdmins) {
                $Schema = Get-CIPPSchemaExtensions | Where-Object { $_.id -match '_cippUser' } | Select-Object -First 1
                $JITAdmins = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users?`$select=id,$($Schema.id)&`$filter=$($Schema.id)/jitAdminEnabled eq true" -tenantid $TenantFilter -ComplexFilter
                $JITAdminIds = $JITAdmins.id
                $Users = $Users | Where-Object { $_.ID -notin $JITAdminIds }
                $UnenforcedAdmins = $UnenforcedAdmins | Where-Object { $_.ID -notin $JITAdminIds }
            }


            $AlertData = [System.Collections.Generic.List[PSCustomObject]]::new()

            foreach ($user in $Users) {
                $AlertData.Add([PSCustomObject]@{
                        Message           = "Admin user $($user.DisplayName) ($($user.UPN)) does not have MFA registered."
                        UserPrincipalName = $user.UPN
                        DisplayName       = $user.DisplayName
                        Id                = $user.ID
                        Tenant            = $TenantFilter
                    })
            }

            foreach ($user in $UnenforcedAdmins) {
                $AlertData.Add([PSCustomObject]@{
                        Message           = "Admin user $($user.DisplayName) ($($user.UPN)) has MFA registered but no enforcement method (Per-User MFA, Security Defaults, or Conditional Access) is active."
                        UserPrincipalName = $user.UPN
                        DisplayName       = $user.DisplayName
                        Id                = $user.ID
                        Tenant            = $TenantFilter
                    })
            }

            if ($AlertData.Count -gt 0) {
                Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
            }
        } else {
            Write-LogMessage -message 'Potentially using Duo for MFA, could not check MFA status for Admins with 100% accuracy' -API 'MFA Alerts - Informational' -tenant $TenantFilter -sev Info
        }
    } catch {
        Write-LogMessage -message "Failed to check MFA status for Admins: $($_.exception.message)" -API 'MFA Alerts - Informational' -tenant $TenantFilter -sev Error
    }
}
