function Invoke-CIPPStandardAnonReportDisable {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    AnonReportDisable
    .CAT
    Global Standards
    .TAG
    "lowimpact"
    .HELPTEXT
    Shows usernames instead of pseudo anonymised names in reports. This standard is required for reporting to work correctly.
    .DOCSDESCRIPTION
    Microsoft announced some APIs and reports no longer return names, to comply with compliance and legal requirements in specific countries. This proves an issue for a lot of MSPs because those reports are often helpful for engineers. This standard applies a setting that shows usernames in those API calls / reports.
    .ADDEDCOMPONENT
    .LABEL
    Enable Usernames instead of pseudo anonymised names in reports
    .IMPACT
    Low Impact
    .POWERSHELLEQUIVALENT
    Update-MgBetaAdminReportSetting -BodyParameter @{displayConcealedNames = $true}
    .RECOMMENDEDBY
    .DOCSDESCRIPTION
    Shows usernames instead of pseudo anonymised names in reports. This standard is required for reporting to work correctly.
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>




    param($Tenant, $Settings)
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
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Anonymous Reports is not disabled' -sev Alert
        }
    }
    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'AnonReport' -FieldValue $CurrentInfo.displayConcealedNames -StoreAs bool -Tenant $tenant
    }
}




