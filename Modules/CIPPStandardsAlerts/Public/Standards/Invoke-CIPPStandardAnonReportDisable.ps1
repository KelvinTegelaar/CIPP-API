function Invoke-CIPPStandardAnonReportDisable {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AnonReportDisable
    .SYNOPSIS
        (Label) Enable Usernames instead of pseudo anonymised names in reports
    .DESCRIPTION
        (Helptext) Shows usernames instead of pseudo anonymised names in reports. This standard is required for reporting to work correctly.
        (DocsDescription) Microsoft announced some APIs and reports no longer return names, to comply with compliance and legal requirements in specific countries. This proves an issue for a lot of MSPs because those reports are often helpful for engineers. This standard applies a setting that shows usernames in those API calls / reports.
    .NOTES
        CAT
            Global Standards
        TAG
        EXECUTIVETEXT
            Configures Microsoft 365 reports to display actual usernames instead of anonymized identifiers, enabling IT administrators to effectively troubleshoot issues and generate meaningful usage reports. This improves operational efficiency and system management capabilities.
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2021-11-16
        POWERSHELLEQUIVALENT
            Update-MgBetaAdminReportSetting -BodyParameter @{displayConcealedNames = \$true}
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    #$Rerun -Type Standard -Tenant $Tenant -API 'allowOTPTokens' -Settings $Settings

    try {
        $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/reportSettings' -tenantid $Tenant -AsApp $true
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the AnonReportDisable state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }

    if ($Settings.remediate -eq $true) {

        if ($CurrentInfo.displayConcealedNames -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Anonymous Reports is already disabled.' -sev Info
        } else {
            try {
                New-GraphPOSTRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/admin/reportSettings' -Type patch -Body '{"displayConcealedNames": false}' -AsApp $true
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Anonymous Reports Disabled.' -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable anonymous reports. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }
    if ($Settings.alert -eq $true) {

        if ($CurrentInfo.displayConcealedNames -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Anonymous Reports is disabled' -sev Info
        } else {
            Write-StandardsAlert -message 'Anonymous Reports is not disabled' -object $CurrentInfo -tenant $tenant -standardName 'AnonReportDisable' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Anonymous Reports is not disabled' -sev Info
        }
    }
    if ($Settings.report -eq $true) {
        $StateIsCorrect = $CurrentInfo.displayConcealedNames ? $false : $true
        Set-CIPPStandardsCompareField -FieldName 'standards.AnonReportDisable' -FieldValue $StateIsCorrect -TenantFilter $tenant
        Add-CIPPBPAField -FieldName 'AnonReport' -FieldValue $CurrentInfo.displayConcealedNames -StoreAs bool -Tenant $tenant
    }
}
