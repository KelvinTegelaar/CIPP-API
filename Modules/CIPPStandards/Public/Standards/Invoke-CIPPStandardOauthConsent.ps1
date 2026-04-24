function Invoke-CIPPStandardOauthConsent {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) OauthConsent
    .SYNOPSIS
        (Label) Require admin consent for applications (Prevent OAuth phishing)
    .DESCRIPTION
        (Helptext) Disables users from being able to consent to applications, except for those specified in the field below
        (DocsDescription) Requires users to get administrator consent before sharing data with applications. You can preapprove specific applications.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "CIS M365 5.0 (1.5.1)"
            "CISA (MS.AAD.4.2v1)"
            "EIDSCA.AP08"
            "EIDSCA.AP09"
            "Essential 8 (1175)"
            "NIST CSF 2.0 (PR.AA-05)"
            "ZTNA21772"
            "ZTNA21774"
            "ZTNA21807"
            "EIDSCAAP08"
            "EIDSCAAP09"
            "EIDSCACP01"
            "EIDSCACP03"
            "EIDSCACP04"
        EXECUTIVETEXT
            Requires administrative approval before employees can grant applications access to company data, preventing unauthorized data sharing and potential security breaches. This protects against malicious applications while allowing approved business tools to function normally.
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.OauthConsent.AllowedApps","label":"Allowed application IDs, comma separated","required":false}
        IMPACT
            Medium Impact
        ADDEDDATE
            2021-11-16
        POWERSHELLEQUIVALENT
            Update-MgPolicyAuthorizationPolicy
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($tenant, $settings)

    try {
        $State = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $tenant
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the OauthConsent state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }
    $AllowedAppIdsForTenant = @($settings.AllowedApps -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    $CompareIncludes = @()
    $CompareIncludesFetched = $false
    try {
        $CompareIncludes = @(New-GraphGetRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies/cipp-consent-policy/includes')
        $CompareIncludesFetched = $true
    } catch {
        $CompareIncludes = @()
    }
    $StateIsCorrect = if ($State.permissionGrantPolicyIdsAssignedToDefaultUserRole -eq 'ManagePermissionGrantsForSelf.cipp-consent-policy') { $true } else { $false }

    if ($Settings.remediate -eq $true) {
        $DidRemediationChange = $false
        try {
            if (-not $CompareIncludesFetched) {
                $Existing = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies/' -tenantid $tenant) | Where-Object -Property id -EQ 'cipp-consent-policy'
                if (!$Existing) {
                    New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies' -Type POST -Body '{ "id":"cipp-consent-policy", "displayName":"Application Consent Policy", "description":"This policy controls the current application consent policies."}' -ContentType 'application/json'
                    # Replaced static web app appid with Office 365 Management by Microsoft's recommendation
                    New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies/cipp-consent-policy/includes' -Type POST -Body '{"permissionClassification":"all","permissionType":"delegated","clientApplicationIds":["00b41c95-dab0-4487-9791-b9d2c32c80f2"]}' -ContentType 'application/json'
                    $DidRemediationChange = $true
                }
            }

            try {
                $ExistingIncludesEntries = @($CompareIncludes)

                foreach ($AllowedApp in $AllowedAppIdsForTenant) {
                    $HasDelegated = $ExistingIncludesEntries | Where-Object {
                        $_.permissionType -eq 'delegated' -and $_.clientApplicationIds -contains $AllowedApp
                    }
                    $HasApplication = $ExistingIncludesEntries | Where-Object {
                        $_.permissionType -eq 'application' -and $_.clientApplicationIds -contains $AllowedApp
                    }

                    if (-not $HasDelegated) {
                        New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies/cipp-consent-policy/includes' -Type POST -Body ('{"permissionType": "delegated","clientApplicationIds": ["' + $AllowedApp + '"]}') -ContentType 'application/json'
                        $DidRemediationChange = $true
                    }

                    if (-not $HasApplication) {
                        New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies/cipp-consent-policy/includes' -Type POST -Body ('{ "permissionType": "Application", "clientApplicationIds": ["' + $AllowedApp + '"] }') -ContentType 'application/json'
                        $DidRemediationChange = $true
                    }
                }
            } catch {
                "Could not add exclusions, probably already exist: $($_)"
            }

            if ($State.permissionGrantPolicyIdsAssignedToDefaultUserRole -notin @('ManagePermissionGrantsForSelf.cipp-consent-policy')) {
                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -Type PATCH -Body '{"permissionGrantPolicyIdsAssignedToDefaultUserRole":["ManagePermissionGrantsForSelf.cipp-consent-policy"]}' -ContentType 'application/json'
                $DidRemediationChange = $true
            }

            if ($DidRemediationChange) {
                try {
                    $State = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $tenant
                    $CompareIncludes = @(New-GraphGetRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies/cipp-consent-policy/includes')
                    $StateIsCorrect = if ($State.permissionGrantPolicyIdsAssignedToDefaultUserRole -eq 'ManagePermissionGrantsForSelf.cipp-consent-policy') { $true } else { $false }
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $tenant -message 'Unable to refresh OauthConsent state/includes after remediation.' -sev Warning
                }
            }

            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode has been enabled.' -sev Info
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to apply Application Consent Mode Error: $ErrorMessage" -sev Error
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode is enabled.' -sev Info
        } else {
            Write-StandardsAlert -message 'Application Consent Mode is not enabled.' -object ($State.defaultUserRolePermissions) -tenant $tenant -standardName 'OauthConsent' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode is not enabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $ExpectedIncludeMap = @{
            'delegated|00b41c95-dab0-4487-9791-b9d2c32c80f2' = @{
                permissionType           = 'delegated'
                permissionClassification = 'all'
                clientApplicationIds     = @('00b41c95-dab0-4487-9791-b9d2c32c80f2')
            }
        }
        foreach ($AllowedApp in $AllowedAppIdsForTenant) {
            $ExpectedIncludeMap["delegated|$AllowedApp"] = @{
                permissionType           = 'delegated'
                permissionClassification = 'all'
                clientApplicationIds     = @($AllowedApp)
            }
            $ExpectedIncludeMap["application|$AllowedApp"] = @{
                permissionType           = 'application'
                permissionClassification = 'all'
                clientApplicationIds     = @($AllowedApp)
            }
        }

        $CurrentIncludesForCompare = @(
            $CompareIncludes | ForEach-Object {
                $CurrentPermissionType = "$($_.permissionType)".ToLowerInvariant()
                $CurrentClientApplicationIds = @($_.clientApplicationIds)

                $IncludeInCurrentConfig = $false
                foreach ($CurrentClientApplicationId in $CurrentClientApplicationIds) {
                    if ($ExpectedIncludeMap.ContainsKey("$CurrentPermissionType|$CurrentClientApplicationId")) {
                        $IncludeInCurrentConfig = $true
                        break
                    }
                }

                if ($IncludeInCurrentConfig) {
                    @{
                        permissionType           = $_.permissionType
                        permissionClassification = $_.permissionClassification
                        clientApplicationIds     = $CurrentClientApplicationIds
                    }
                }
            }
        )
        $CurrentIncludesForCompare = @(
            $CurrentIncludesForCompare | Sort-Object permissionType, @{ Expression = { ($_.clientApplicationIds -join ',') } }
        )

        $ExpectedIncludesForCompare = @(
            @($ExpectedIncludeMap.Values) | Sort-Object permissionType, @{ Expression = { ($_.clientApplicationIds -join ',') } }
        )

        $IncludesAreConfigured = $true
        foreach ($ExpectedInclude in $ExpectedIncludesForCompare) {
            $ExpectedPermissionType = $ExpectedInclude.permissionType
            $ExpectedClientApplicationIds = @($ExpectedInclude.clientApplicationIds)
            $ExpectedClassification = $ExpectedInclude.permissionClassification

            $MatchingEntry = $CurrentIncludesForCompare | Where-Object {
                $_.permissionType -eq $ExpectedPermissionType -and
                $_.permissionClassification -eq $ExpectedClassification -and
                ((@($_.clientApplicationIds) | Sort-Object) -join ',') -eq (($ExpectedClientApplicationIds | Sort-Object) -join ',')
            } | Select-Object -First 1

            if (-not $MatchingEntry) {
                $IncludesAreConfigured = $false
                break
            }
        }

        $StateIsCorrect = ($State.permissionGrantPolicyIdsAssignedToDefaultUserRole -eq 'ManagePermissionGrantsForSelf.cipp-consent-policy') -and $IncludesAreConfigured

        Add-CIPPBPAField -FieldName 'OauthConsent' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant

        $CurrentValue = @{
            permissionGrantPolicyIdsAssignedToDefaultUserRole = $State.permissionGrantPolicyIdsAssignedToDefaultUserRole
            includes = $CurrentIncludesForCompare
        }
        $ExpectedValue = @{
            permissionGrantPolicyIdsAssignedToDefaultUserRole = @('ManagePermissionGrantsForSelf.cipp-consent-policy')
            includes = $ExpectedIncludesForCompare
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.OauthConsent' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $tenant
    }
}
