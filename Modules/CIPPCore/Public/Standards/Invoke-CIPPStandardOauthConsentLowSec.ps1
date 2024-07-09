function Invoke-CIPPStandardOauthConsentLowSec {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    OauthConsentLowSec
    .CAT
    Entra (AAD) Standards
    .TAG
    "mediumimpact"
    .HELPTEXT
    Sets the default oauth consent level so users can consent to applications that have low risks.
    .DOCSDESCRIPTION
    Allows users to consent to applications with low assigned risk.
    .LABEL
    Allow users to consent to applications with low security risk (Prevent OAuth phishing. Lower impact, less secure)
    .IMPACT
    Medium Impact
    .POWERSHELLEQUIVALENT
    Update-MgPolicyAuthorizationPolicy
    .RECOMMENDEDBY
    .DOCSDESCRIPTION
    Sets the default oauth consent level so users can consent to applications that have low risks.
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>




    param($Tenant, $Settings)
    $State = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $tenant)
    If ($Settings.remediate -eq $true) {
        try {
            if ($State.permissionGrantPolicyIdsAssignedToDefaultUserRole -notin @('managePermissionGrantsForSelf.microsoft-user-default-low')) {
                Write-Host 'Going to set'
                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -Type PATCH -Body '{"permissionGrantPolicyIdsAssignedToDefaultUserRole":["managePermissionGrantsForSelf.microsoft-user-default-low"]}' -ContentType 'application/json'
            }
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode(microsoft-user-default-low) has been enabled.' -sev Info
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to apply Application Consent Mode (microsoft-user-default-low) Error: $ErrorMessage" -sev Error
        }
    }
    if ($Settings.alert -eq $true) {

        if ($State.permissionGrantPolicyIdsAssignedToDefaultUserRole -notin @('managePermissionGrantsForSelf.microsoft-user-default-low')) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode(microsoft-user-default-low) is not enabled.' -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode(microsoft-user-default-low) is enabled.' -sev Info
        }
    }
    if ($Settings.report -eq $true) {
        if ($State.permissionGrantPolicyIdsAssignedToDefaultUserRole -notin @('managePermissionGrantsForSelf.microsoft-user-default-low')) {
            $State.permissionGrantPolicyIdsAssignedToDefaultUserRole = $false
        } else {
            $State.permissionGrantPolicyIdsAssignedToDefaultUserRole = $true
        }
        Add-CIPPBPAField -FieldName 'OauthConsentLowSec' -FieldValue $State.permissionGrantPolicyIdsAssignedToDefaultUserRole -StoreAs bool -Tenant $tenant
    }
}




