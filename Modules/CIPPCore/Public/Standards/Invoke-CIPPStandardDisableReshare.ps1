function Invoke-CIPPStandardDisableReshare {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableReshare
    .SYNOPSIS
        (Label) Disable Re-sharing by External Users
    .DESCRIPTION
        (Helptext) Disables the ability for external users to share files they don't own. Sharing links can only be made for People with existing access
        (DocsDescription) Disables the ability for external users to share files they don't own. Sharing links can only be made for People with existing access. This is a tenant wide setting and overrules any settings set on the site level
    .NOTES
        CAT
            SharePoint Standards
        TAG
            "CIS"
        ADDEDCOMPONENT
        IMPACT
            High Impact
        ADDEDDATE
            2022-06-15
        POWERSHELLEQUIVALENT
            Update-MgBetaAdminSharePointSetting
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'DisableReshare' -TenantFilter $Tenant -RequiredCapabilities @('SHAREPOINTWAC', 'SHAREPOINTSTANDARD', 'SHAREPOINTENTERPRISE', 'ONEDRIVE_BASIC', 'ONEDRIVE_ENTERPRISE')
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DisableReshare'

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true

    If ($Settings.remediate -eq $true) {

        if ($CurrentInfo.isResharingByExternalUsersEnabled) {
            try {
                $body = '{"isResharingByExternalUsersEnabled": "False"}'
                $null = New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type patch -Body $body -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled guests from resharing files' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable guests from resharing files: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Guests are already disabled from resharing files' -sev Info
        }
    }
    if ($Settings.alert -eq $true) {

        if ($CurrentInfo.isResharingByExternalUsersEnabled) {
            Write-StandardsAlert -message 'Guests are allowed to reshare files' -object $CurrentInfo -tenant $tenant -standardName 'DisableReshare' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Guests are allowed to reshare files' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Guests are not allowed to reshare files' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $state = $CurrentInfo.isResharingByExternalUsersEnabled ? ($CurrentInfo | Select-Object isResharingByExternalUsersEnabled) : $true
        Set-CIPPStandardsCompareField -FieldName 'standards.DisableReshare' -FieldValue $state -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableReshare' -FieldValue $CurrentInfo.isResharingByExternalUsersEnabled -StoreAs bool -Tenant $tenant
    }
}
