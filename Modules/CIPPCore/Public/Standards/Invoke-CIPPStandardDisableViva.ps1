function Invoke-CIPPStandardDisableViva {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableViva
    .SYNOPSIS
        (Label) Disable daily Insight/Viva reports
    .DESCRIPTION
        (Helptext) Disables the daily viva reports for all users. This standard requires the CIPP-SAM application to have the Company Administrator (Global Admin) role in the tenant. Enable this using CIPP > Advanced > Super Admin > SAM App Roles. Activate the roles with a CPV refresh.
        (DocsDescription) Disables the daily viva reports for all users. This standard requires the CIPP-SAM application to have the Company Administrator (Global Admin) role in the tenant. Enable this using CIPP \> Advanced \> Super Admin \> SAM App Roles. Activate the roles with a CPV refresh.
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Disables daily Microsoft Viva Insights reports that are automatically sent to employees, reducing email volume and allowing organizations to control when and how productivity insights are shared. This can help prevent information overload while maintaining the ability to access insights when needed.
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2022-05-25
        POWERSHELLEQUIVALENT
            Set-UserBriefingConfig
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    try {
        # TODO This does not work without Global Admin permissions for some reason. Throws an "EXCEPTION: Tenant admin role is required" error. -Bobby
        $CurrentSetting = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/organization/$Tenant/settings/peopleInsights" -tenantid $Tenant -AsApp $true
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to get Viva insights settings. Error: $ErrorMessage" -sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($CurrentSetting.isEnabledInOrganization -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Viva is already disabled.' -sev Info
        } else {
            try {
                # TODO This does not work without Global Admin permissions for some reason. Throws an "EXCEPTION: Tenant admin role is required" error. -Bobby
                New-GraphPOSTRequest -Uri "https://graph.microsoft.com/beta/organization/$Tenant/settings/peopleInsights" -tenantid $Tenant -Type PATCH -Body '{"isEnabledInOrganization": false}' -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Disabled Viva insights' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to disable Viva for all users. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($CurrentSetting.isEnabledInOrganization -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Viva is disabled' -sev Info
        } else {
            Write-StandardsAlert -message 'Viva is not disabled' -object $CurrentSetting -tenant $Tenant -standardName 'DisableViva' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Viva is not disabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = [PSCustomObject]@{
            DisableViva = -not $CurrentSetting.isEnabledInOrganization
        }
        $ExpectedValue = [PSCustomObject]@{
            DisableViva = $true
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.DisableViva' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableViva' -FieldValue $CurrentSetting.isEnabledInOrganization -StoreAs bool -Tenant $Tenant
    }

}
