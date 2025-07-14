function Invoke-CIPPStandardintuneDeviceRetirementDays {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) intuneDeviceRetirementDays
    .SYNOPSIS
        (Label) Set inactive device retirement days
    .DESCRIPTION
        (Helptext) A value between 0 and 270 is supported. A value of 0 disables retirement, retired devices are removed from Intune after the specified number of days.
        (DocsDescription) A value between 0 and 270 is supported. A value of 0 disables retirement, retired devices are removed from Intune after the specified number of days.
    .NOTES
        CAT
            Intune Standards
        TAG
        ADDEDCOMPONENT
            {"type":"number","name":"standards.intuneDeviceRetirementDays.days","label":"Maximum days (0 equals disabled)"}
        IMPACT
            Low Impact
        ADDEDDATE
            2023-05-19
        POWERSHELLEQUIVALENT
            Graph API
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    Test-CIPPStandardLicense -StandardName 'intuneDeviceRetirementDays' -TenantFilter $Tenant -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1')
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'intuneDeviceRetirementDays'

    $CurrentInfo = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/managedDeviceCleanupRules' -tenantid $Tenant)
    $StateIsCorrect = if ($CurrentInfo.DeviceInactivityBeforeRetirementInDays -eq $Settings.days) { $true } else { $false }

    if ($Settings.remediate -eq $true) {

        if ($CurrentInfo.DeviceInactivityBeforeRetirementInDays -eq $Settings.days) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "DeviceInactivityBeforeRetirementInDays for $($Settings.days) days is already enabled." -sev Info
        } else {
            if ($CurrentInfo) {
                $Type = 'Patch'
                $id = "('$($CurrentInfo.id)')"
            } else {
                $Type = 'Post'
            }
            try {
                $body = '{"displayName":"Default Policy","description":"Default Policy","deviceCleanupRulePlatformType":"all","deviceInactivityBeforeRetirementInDays":' + $Settings.days + '}'
                (New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDeviceCleanupRules$id" -Type $Type -Body $body -ContentType 'application/json')
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Enabled DeviceInactivityBeforeRetirementInDays for $($Settings.days) days." -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable DeviceInactivityBeforeRetirementInDays. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DeviceInactivityBeforeRetirementInDays is enabled.' -sev Info
        } else {
            Write-StandardsAlert -message 'DeviceInactivityBeforeRetirementInDays is not enabled' -object $CurrentInfo -tenant $tenant -standardName 'intuneDeviceRetirementDays' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DeviceInactivityBeforeRetirementInDays is not enabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $state = $StateIsCorrect ? $true : $CurrentInfo.DeviceInactivityBeforeRetirementInDays
        Set-CIPPStandardsCompareField -FieldName 'standards.intuneDeviceRetirementDays' -FieldValue $state -Tenant $tenant
        Add-CIPPBPAField -FieldName 'intuneDeviceRetirementDays' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
