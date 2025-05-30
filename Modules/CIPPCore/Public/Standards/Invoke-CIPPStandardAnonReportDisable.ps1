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

    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/reportSettings' -tenantid $Tenant -AsApp $true

    If ($Settings.remediate -eq $true) {

        if ($CurrentInfo.displayConcealedNames -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Anonymous Reports is already disabled.' -sev Info
        } else {
            try {
                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/admin/reportSettings' -Type patch -Body '{"displayConcealedNames": false}' -ContentType 'application/json' -AsApp $true
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Anonymous Reports Disabled.' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable anonymous reports. Error: $ErrorMessage" -sev Error
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
