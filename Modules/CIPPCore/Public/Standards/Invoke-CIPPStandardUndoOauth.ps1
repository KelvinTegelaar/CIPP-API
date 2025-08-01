function Invoke-CIPPStandardUndoOauth {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) UndoOauth
    .SYNOPSIS
        (Label) Undo App Consent Standard
    .DESCRIPTION
        (Helptext) Disables App consent and set to Allow user consent for apps
        (DocsDescription) Disables App consent and set to Allow user consent for apps
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        ADDEDCOMPONENT
        IMPACT
            High Impact
        ADDEDDATE
            2022-01-07
        POWERSHELLEQUIVALENT
            Update-MgPolicyAuthorizationPolicy
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'UndoOauth'

    try {
        $CurrentState = New-GraphGetRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy?$select=permissionGrantPolicyIdsAssignedToDefaultUserRole'
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the App Consent state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $StateIsCorrect = ($CurrentState.permissionGrantPolicyIdsAssignedToDefaultUserRole -eq 'ManagePermissionGrantsForSelf.microsoft-user-default-legacy')

    If ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Application Consent Mode is already disabled.' -sev Info
        } else {
            try {
                $GraphRequest = @{
                    tenantid = $tenant
                    uri = 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy'
                    AsApp = $false
                    Type = 'PATCH'
                    ContentType = 'application/json'
                    Body = '{"permissionGrantPolicyIdsAssignedToDefaultUserRole":["ManagePermissionGrantsForSelf.microsoft-user-default-legacy"]}'
                }
                New-GraphPostRequest @GraphRequest
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode has been disabled.' -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set Application Consent Mode to disabled." -sev Error -LogData $_
            }
        }

    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Application Consent Mode is disabled.' -sev Info
        } else {
            Write-StandardsAlert -message "Application Consent Mode is not disabled." -object $CurrentState -tenant $Tenant -standardName 'UndoOauth' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Application Consent Mode is not disabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'UndoOauth' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
        if ($StateIsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.UndoOauth' -FieldValue $FieldValue -Tenant $Tenant
    }
}
