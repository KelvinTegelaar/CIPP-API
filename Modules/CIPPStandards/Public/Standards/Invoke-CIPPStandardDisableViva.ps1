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
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    try {
        $CurrentSetting = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/organization/$Tenant/settings/peopleInsights" -tenantid $Tenant -AsApp $true
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to get Viva insights settings. Error: $ErrorMessage" -sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        if ($CurrentSetting.isEnabledInOrganization -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Viva is already disabled.' -sev Info
        } else {
            try {
                New-GraphPOSTRequest -Uri "https://graph.microsoft.com/beta/organization/$Tenant/settings/peopleInsights" -tenantid $Tenant -Type PATCH -Body '{"isEnabledInOrganization": false}' -ContentType 'application/json' -AsApp $true
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Disabled Viva insights' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                # Microsoft rejects this write with an empty UnknownError unless CIPP-SAM holds Global Administrator in the tenant
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not disable Viva insights. Microsoft only accepts this change when the CIPP-SAM application has the Global Administrator role in the tenant (CIPP > Advanced > Super Admin > SAM App Roles, then a CPV refresh). Error: $ErrorMessage" -sev Warning
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
    }

}
