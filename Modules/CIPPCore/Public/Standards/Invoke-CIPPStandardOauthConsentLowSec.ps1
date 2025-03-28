function Invoke-CIPPStandardOauthConsentLowSec {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) OauthConsentLowSec
    .SYNOPSIS
        (Label) Allow users to consent to applications with low security risk (Prevent OAuth phishing. Lower impact, less secure)
    .DESCRIPTION
        (Helptext) Sets the default oauth consent level so users can consent to applications that have low risks.
        (DocsDescription) Allows users to consent to applications with low assigned risk.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "IntegratedApps"
        IMPACT
            Medium Impact
        ADDEDDATE
            2022-08-16
        POWERSHELLEQUIVALENT
            Update-MgPolicyAuthorizationPolicy
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/entra-aad-standards#medium-impact
    #>

    param($Tenant, $Settings)

    $State = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $tenant)
    $PermissionState = (New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/servicePrincipals(appId='00000003-0000-0000-c000-000000000000')/delegatedPermissionClassifications" -tenantid $tenant) | Select-Object -Property permissionName

    $requiredPermissions = @('offline_access', 'openid', 'User.Read', 'profile', 'email')
    $missingPermissions = $requiredPermissions | Where-Object { $PermissionState.permissionName -notcontains $_ }

    $Standards = Get-CIPPStandards -Tenant $tenant
    $ConflictingStandard = $Standards | Where-Object -Property Standard -EQ 'OauthConsent'

    if ($Settings.remediate -eq $true) {
        if ($State.permissionGrantPolicyIdsAssignedToDefaultUserRole -in @('managePermissionGrantsForSelf.microsoft-user-default-low')) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode(microsoft-user-default-low) is already enabled.' -sev Info
        } elseif ($ConflictingStandard -and $State.permissionGrantPolicyIdsAssignedToDefaultUserRole -contains 'ManagePermissionGrantsForSelf.cipp-consent-policy') {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'There is a conflicting OAuth Consent policy standard enabled for this tenant. Remove the Require admin consent for applications (Prevent OAuth phishing) standard from this tenant to apply the low security standard.' -sev Error
        } else {
            try {
                $GraphParam = @{
                    tenantid    = $tenant
                    Uri         = 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy'
                    Type        = 'PATCH'
                    Body        = @{
                        permissionGrantPolicyIdsAssignedToDefaultUserRole = @('managePermissionGrantsForSelf.microsoft-user-default-low')
                    } | ConvertTo-Json
                    ContentType = 'application/json'
                }
                $null = New-GraphPostRequest @GraphParam
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode(microsoft-user-default-low) has been enabled.' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to apply Application Consent Mode (microsoft-user-default-low) Error: $ErrorMessage" -sev Error
            }
        }

        if ($missingPermissions.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'All permissions for Application Consent already assigned.' -sev Info
        } else {
            try {
                $missingPermissions | ForEach-Object {
                    $GraphParam = @{
                        tenantid    = $tenant
                        Uri         = "https://graph.microsoft.com/beta/servicePrincipals(appId='00000003-0000-0000-c000-000000000000')/delegatedPermissionClassifications"
                        Type        = 'POST'
                        Body        = @{
                            permissionName = $_
                            classification = 'low'
                        } | ConvertTo-Json
                        ContentType = 'application/json'
                    }
                    $null = New-GraphPostRequest @GraphParam
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Permission $_ has been added to low Application Consent" -sev Info
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to apply low consent permissions Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($State.permissionGrantPolicyIdsAssignedToDefaultUserRole -notin @('managePermissionGrantsForSelf.microsoft-user-default-low')) {
            Write-StandardsAlert -message 'Application Consent Mode(microsoft-user-default-low) is not enabled' -object $State -tenant $tenant -standardName 'OauthConsentLowSec' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode(microsoft-user-default-low) is not enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode(microsoft-user-default-low) is enabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        if ($State.permissionGrantPolicyIdsAssignedToDefaultUserRole -notin @('managePermissionGrantsForSelf.microsoft-user-default-low')) {
            $State.permissionGrantPolicyIdsAssignedToDefaultUserRole = $false
            $ValueField = @{
                authorizationPolicy       = $State.permissionGrantPolicyIdsAssignedToDefaultUserRole
                permissionClassifications = $PermissionState
            }
            if ($ConflictingStandard) {
                $ValueField.conflictingStandard = @{
                    name       = $ConflictingStandard.Standard
                    templateid = $ConflictingStandard.TemplateId
                }
            }
        } else {
            $State.permissionGrantPolicyIdsAssignedToDefaultUserRole = $true
            $ValueField = $true
        }
        Add-CIPPBPAField -FieldName 'OauthConsentLowSec' -FieldValue $State.permissionGrantPolicyIdsAssignedToDefaultUserRole -StoreAs bool -Tenant $tenant
        Set-CIPPStandardsCompareField -FieldName 'standards.OauthConsentLowSec' -FieldValue $ValueField -Tenant $tenant
    }
}
