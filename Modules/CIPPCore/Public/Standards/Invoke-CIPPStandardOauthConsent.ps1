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
            "CIS"
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
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/entra-aad-standards#medium-impact
    #>

    param($tenant, $settings)

    $State = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $tenant
    $StateIsCorrect = if ($State.permissionGrantPolicyIdsAssignedToDefaultUserRole -eq 'managePermissionGrantsForSelf.cipp-consent-policy') { $true } else { $false }

    if ($Settings.remediate -eq $true) {
        $AllowedAppIdsForTenant = $settings.AllowedApps -split ',' | ForEach-Object { $_.Trim() }
        try {
            $Existing = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies/' -tenantid $tenant) | Where-Object -Property id -EQ 'cipp-consent-policy'
            if (!$Existing) {
                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies' -Type POST -Body '{ "id":"cipp-consent-policy", "displayName":"Application Consent Policy", "description":"This policy controls the current application consent policies."}' -ContentType 'application/json'
                # Replaced static web app appid with Office 365 Management by Microsoft's recommendation
                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies/cipp-consent-policy/includes' -Type POST -Body '{"permissionClassification":"all","permissionType":"delegated","clientApplicationIds":["00b41c95-dab0-4487-9791-b9d2c32c80f2"]}' -ContentType 'application/json'
            }

            try {
                $ExistingIncludes = New-GraphGetRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies/cipp-consent-policy/includes'

                $ExistingAppIds = foreach ($entry in $ExistingIncludes.value) {
                    $entry.clientApplicationIds
                }
                $ExistingAppIds = $ExistingAppIds | Sort-Object -Unique

                foreach ($AllowedApp in $AllowedAppIdsForTenant) {
                    if ($AllowedApp -and ($AllowedApp -notin $ExistingAppIds)) {
                        Write-Host "Adding missing approved app: $AllowedApp"
                        New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies/cipp-consent-policy/includes' -Type POST -Body ('{"permissionType": "delegated","clientApplicationIds": ["' + $AllowedApp + '"]}') -ContentType 'application/json'
                        New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies/cipp-consent-policy/includes' -Type POST -Body ('{ "permissionType": "Application", "clientApplicationIds": ["' + $AllowedApp + '"] }') -ContentType 'application/json'
                    }
                }
            } catch {
                "Could not add exclusions, probably already exist: $($_)"
            }

            if ($State.permissionGrantPolicyIdsAssignedToDefaultUserRole -notin @('managePermissionGrantsForSelf.cipp-consent-policy')) {
                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -Type PATCH -Body '{"permissionGrantPolicyIdsAssignedToDefaultUserRole":["managePermissionGrantsForSelf.cipp-consent-policy"]}' -ContentType 'application/json'
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
        Add-CIPPBPAField -FieldName 'OauthConsent' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
        if ($StateIsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = $State | Select-Object -Property permissionGrantPolicyIdsAssignedToDefaultUserRole
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.OauthConsent' -FieldValue $FieldValue -Tenant $tenant
    }
}
