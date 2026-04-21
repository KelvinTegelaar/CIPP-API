function Update-AppManagementPolicy {
    <#
    .SYNOPSIS
        Check and update app management policies for credential restrictions

    .DESCRIPTION
        Retrieves tenant default app management policy and app management policies to check if
        passwordCredential or keyCredential creation is restricted. If the default policy blocks
        credential addition and the targeted app doesn't have an exemption, creates or updates a policy
        to allow the app to manage credentials.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $TenantFilter = $env:TenantID,
        $ApplicationId = $env:ApplicationID,
        $headers
    )

    try {
        # Create bulk request to fetch both policies at once
        $Requests = @(
            @{
                id     = 'defaultPolicy'
                method = 'GET'
                url    = '/policies/defaultAppManagementPolicy'
            }
            @{
                id     = 'appPolicies'
                method = 'GET'
                url    = '/policies/appManagementPolicies'
            }
            @{
                id     = 'appRegistration'
                method = 'GET'
                url    = "applications(appId='$ApplicationId')?`$select=id,appId,displayName"
            }
        )

        # Execute bulk request
        $Results = New-GraphBulkRequest -Requests $Requests -NoAuthCheck $true -asapp $true -tenantid $TenantFilter -headers $headers
        # Parse results
        $DefaultPolicy = ($Results | Where-Object { $_.id -eq 'defaultPolicy' }).body
        $AppPolicies = ($Results | Where-Object { $_.id -eq 'appPolicies' }).body.value
        $CIPPApp = ($Results | Where-Object { $_.id -eq 'appRegistration' }).body

        # Check if CIPP-SAM app is targeted by any policies
        $CIPPAppTargeted = $false
        $CIPPAppPolicyId = $null
        if ($AppPolicies -and $ApplicationId) {
            # Build bulk requests to get appliesTo for each policy
            $AppliesToRequests = @($AppPolicies | ForEach-Object {
                    @{
                        id     = $_.id
                        method = 'GET'
                        url    = "/policies/appManagementPolicies/$($_.id)/appliesTo"
                    }
                })

            if ($AppliesToRequests.Count -gt 0) {
                $AppliesToResults = New-GraphBulkRequest -Requests $AppliesToRequests -NoAuthCheck $true -asapp $true -tenantid $TenantFilter -headers $headers
                # Find which policy (if any) targets the app
                $CIPPPolicyResult = $AppliesToResults | Where-Object { $_.body.value.appId -contains $ApplicationId } | Select-Object -First 1
                if ($CIPPPolicyResult) {
                    $CIPPAppTargeted = $true
                    $CIPPAppPolicyId = $CIPPPolicyResult.id
                }
            }
        }

        # Check for credential restrictions across all policies
        $PasswordAdditionBlocked = $false
        $SymmetricKeyAdditionBlocked = $false
        $AsymmetricKeyAdditionBlocked = $false
        $PasswordLifetimeRestricted = $false
        $KeyLifetimeRestricted = $false

        # Helper function to check restrictions in a policy
        function Test-PolicyRestrictions {
            param($Policy, [switch]$IsDefaultPolicy)

            # Default policy has applicationRestrictions, app-specific policies have restrictions
            $pwdCreds = if ($IsDefaultPolicy) { $Policy.applicationRestrictions.passwordCredentials } else { $Policy.restrictions.passwordCredentials }
            $keyCreds = if ($IsDefaultPolicy) { $Policy.applicationRestrictions.keyCredentials } else { $Policy.restrictions.keyCredentials }

            if ($pwdCreds) {
                foreach ($restriction in $pwdCreds | Where-Object { $_.state -eq 'enabled' }) {
                    switch ($restriction.restrictionType) {
                        'passwordAddition' { $PasswordAdditionBlocked = $true }
                        'symmetricKeyAddition' { $SymmetricKeyAdditionBlocked = $true }
                        'passwordLifetime' { $PasswordLifetimeRestricted = $true }
                        'symmetricKeyLifetime' { $PasswordLifetimeRestricted = $true }
                    }
                }
            }

            if ($keyCreds) {
                foreach ($restriction in $keyCreds | Where-Object { $_.state -eq 'enabled' }) {
                    switch ($restriction.restrictionType) {
                        'asymmetricKeyLifetime' { $KeyLifetimeRestricted = $true }
                        'trustedCertificateAuthority' { $AsymmetricKeyAdditionBlocked = $true }
                    }
                }
            }
        }

        # Check default policy (uses applicationRestrictions structure)
        if ($DefaultPolicy) {
            Test-PolicyRestrictions -Policy $DefaultPolicy -IsDefaultPolicy
        }

        # Check app-specific policies (use restrictions structure)
        if ($AppPolicies) {
            foreach ($AppPolicy in $AppPolicies | Where-Object { $_.isEnabled -eq $true }) {
                Test-PolicyRestrictions -Policy $AppPolicy
            }
        }

        # Determine if default policy blocks credential addition
        $DefaultPolicyBlocksCredentials = $false
        if ($DefaultPolicy.applicationRestrictions.passwordCredentials) {
            $DefaultPolicyBlocksCredentials = ($DefaultPolicy.applicationRestrictions.passwordCredentials | Where-Object { $_.restrictionType -in @('passwordAddition', 'symmetricKeyAddition') -and $_.state -eq 'enabled' }).Count -gt 0
        }

        # If default policy blocks credentials and CIPP app doesn't have an exemption, create/update policy
        $PolicyAction = $null
        if ($DefaultPolicyBlocksCredentials -and $CIPPApp) {
            # Check if a CIPP-SAM Exemption Policy already exists
            $ExistingExemptionPolicy = $AppPolicies | Where-Object { $_.displayName -eq 'CIPP Exemption Policy' } | Select-Object -First 1

            # Check if CIPP app has a policy that allows credentials
            $CIPPHasExemption = $false
            if ($CIPPAppPolicyId) {
                $CIPPPolicy = $AppPolicies | Where-Object { $_.id -eq $CIPPAppPolicyId }
                # Check if the policy explicitly allows credentials (no enabled passwordAddition/symmetricKeyAddition restriction)
                if ($CIPPPolicy.restrictions.passwordCredentials) {
                    $CIPPHasExemption = -not ($CIPPPolicy.restrictions.passwordCredentials | Where-Object { $_.restrictionType -in @('passwordAddition', 'symmetricKeyAddition') -and $_.state -eq 'enabled' })
                } else {
                    # No password restrictions means it allows credentials
                    $CIPPHasExemption = $true
                }
            }

            if (-not $CIPPHasExemption) {
                # Need to create or update a policy for CIPP
                try {
                    # Define policy structure with disabled restrictions
                    $PolicyBody = @{
                        displayName  = 'CIPP Exemption Policy'
                        description  = 'Allows CIPP app to manage credentials'
                        isEnabled    = $true
                        restrictions = @{
                            passwordCredentials = @(
                                @{
                                    restrictionType                     = 'passwordAddition'
                                    state                               = 'disabled'
                                    restrictForAppsCreatedAfterDateTime = '0001-01-01T00:00:00Z'
                                }
                                @{
                                    restrictionType                     = 'symmetricKeyAddition'
                                    state                               = 'disabled'
                                    restrictForAppsCreatedAfterDateTime = '0001-01-01T00:00:00Z'
                                }
                            )
                            keyCredentials      = @()
                        }
                    }

                    if ($CIPPAppPolicyId) {
                        # Update existing policy that's already assigned to the app
                        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/policies/appManagementPolicies/$CIPPAppPolicyId" -type PATCH -body ($PolicyBody | ConvertTo-Json -Depth 10) -asapp $true -NoAuthCheck $true -tenantid $TenantFilter -headers $headers
                        $PolicyAction = "Updated existing policy $CIPPAppPolicyId to allow credentials"
                    } elseif ($ExistingExemptionPolicy) {
                        # Exemption policy exists but not assigned to app - update and assign it
                        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/policies/appManagementPolicies/$($ExistingExemptionPolicy.id)" -type PATCH -body ($PolicyBody | ConvertTo-Json -Depth 10) -asapp $true -NoAuthCheck $true -headers $headers

                        if ($CIPPApp.id) {
                            # Assign existing policy to CIPP-SAM application
                            $AssignBody = @{
                                '@odata.id' = "https://graph.microsoft.com/beta/policies/appManagementPolicies/$($ExistingExemptionPolicy.id)"
                            }
                            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/applications/$($CIPPApp.id)/appManagementPolicies/`$ref" -type POST -body ($AssignBody | ConvertTo-Json) -asapp $true -NoAuthCheck $true -tenantid $TenantFilter -headers $headers
                            $PolicyAction = "Updated and assigned existing policy $($ExistingExemptionPolicy.id) to CIPP-SAM"
                            $CIPPAppPolicyId = $ExistingExemptionPolicy.id
                            $CIPPAppTargeted = $true
                        } else {
                            $PolicyAction = "Updated policy $($ExistingExemptionPolicy.id) but failed to assign: CIPP application not found"
                        }
                    } else {
                        # Create new policy and assign to CIPP-SAM app
                        $CreatedPolicy = New-GraphPostRequest -uri 'https://graph.microsoft.com/v1.0/policies/appManagementPolicies' -type POST -body ($PolicyBody | ConvertTo-Json -Depth 10) -asapp $true -NoAuthCheck $true -headers $headers

                        if ($CIPPApp.id) {
                            # Assign policy to CIPP-SAM application using beta endpoint
                            $AssignBody = @{
                                '@odata.id' = "https://graph.microsoft.com/beta/policies/appManagementPolicies/$($CreatedPolicy.id)"
                            }
                            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/applications/$($CIPPApp.id)/appManagementPolicies/`$ref" -type POST -body ($AssignBody | ConvertTo-Json) -asapp $true -NoAuthCheck $true -headers $headers
                            $PolicyAction = "Created new policy $($CreatedPolicy.id) and assigned to CIPP-SAM"
                            $CIPPAppPolicyId = $CreatedPolicy.id
                            $CIPPAppTargeted = $true
                        } else {
                            $PolicyAction = "Created new policy $($CreatedPolicy.id) but failed to assign: CIPP application not found"
                        }
                    }
                } catch {
                    $PolicyAction = "Failed to update policy: $($_.Exception.Message)"
                }
            } else {
                $PolicyAction = 'CIPP-SAM app is already exempt from credential restrictions. No action needed.'
            }
        }

        # Build result object
        $PolicyInfo = [PSCustomObject]@{
            DefaultPolicy                   = $DefaultPolicy
            AppPolicies                     = $AppPolicies
            CIPPAppTargeted                 = $CIPPAppTargeted
            CIPPAppPolicyId                 = $CIPPAppPolicyId
            CIPPHasExemption                = $CIPPHasExemption
            PolicyAction                    = $PolicyAction
            PasswordAdditionBlocked         = $PasswordAdditionBlocked
            SymmetricKeyAdditionBlocked     = $SymmetricKeyAdditionBlocked
            PasswordLifetimeRestricted      = $PasswordLifetimeRestricted
            KeyLifetimeRestricted           = $KeyLifetimeRestricted
            AnyCredentialCreationRestricted = $PasswordAdditionBlocked -or $SymmetricKeyAdditionBlocked
            PolicyCount                     = if ($AppPolicies) { $AppPolicies.Count } else { 0 }
            EnabledPolicyCount              = if ($AppPolicies) { ($AppPolicies | Where-Object { $_.isEnabled -eq $true }).Count } else { 0 }
        }

        return $PolicyInfo

    } catch {
        Write-Warning "Failed to retrieve app management policies: $($_.Exception.Message)"
        return $null
    }
}
