function Invoke-CIPPStandardOauthConsent {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($tenant, $settings)
    $State = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $tenant

    If ($Settings.remediate -eq $true) {
        $AllowedAppIdsForTenant = $Settings.AllowedApps -split ','
        try {
            if ($State.permissionGrantPolicyIdsAssignedToDefaultUserRole -notin @('ManagePermissionGrantsForSelf.cipp-1sent-policy')) {
                $Existing = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies/' -tenantid $tenant) | Where-Object -Property id -EQ 'cipp-consent-policy'
                if (!$Existing) {
                    New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies' -Type POST -Body '{ "id":"cipp-consent-policy", "displayName":"Application Consent Policy", "description":"This policy controls the current application consent policies."}' -ContentType 'application/json'
                    New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies/cipp-consent-policy/includes' -Type POST -Body '{"permissionClassification":"all","permissionType":"delegated","clientApplicationIds":["d414ee2d-73e5-4e5b-bb16-03ef55fea597"]}' -ContentType 'application/json'
                }
                try {
                    foreach ($AllowedApp in $AllowedAppIdsForTenant) {
                        Write-Host "$AllowedApp"
                        New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies/cipp-consent-policy/includes' -Type POST -Body ('{"permissionType": "delegated","clientApplicationIds": ["' + $AllowedApp + '"]}') -ContentType 'application/json'
                        New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies/cipp-consent-policy/includes' -Type POST -Body ('{ "permissionType": "Application", "clientApplicationIds": ["' + $AllowedApp + '"] }') -ContentType 'application/json'
                    }
                } catch {
                    "Could not add exclusions, probably already exist: $($_)"
                }
                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -Type PATCH -Body '{"permissionGrantPolicyIdsAssignedToDefaultUserRole":["managePermissionGrantsForSelf.cipp-consent-policy"]}' -ContentType 'application/json'
            }
            if ($AllowedAppIdsForTenant) {
            }

            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode has been enabled.' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to apply Application Consent Mode Error: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.alert -eq $true) {

        if ($State.permissionGrantPolicyIdsAssignedToDefaultUserRole -eq 'managePermissionGrantsForSelf.cipp-consent-policy') {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode is not enabled.' -sev Alert
        }
    }
    if ($Settings.report -eq $true) {
        if ($State.permissionGrantPolicyIdsAssignedToDefaultUserRole -eq 'managePermissionGrantsForSelf.cipp-consent-policy') { $UserQuota = $true } else { $UserQuota = $false }
        Add-CIPPBPAField -FieldName 'OauthConsent' -FieldValue $UserQuota -StoreAs bool -Tenant $tenant
    }
}
