Function Invoke-CIPPStandardIntuneWindowsDiagnostic {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) IntuneWindowsDiagnostic
    .SYNOPSIS
        (Label) Set Intune Windows diagnostic data settings
    .DESCRIPTION
        (Helptext) **Some features require Windows E3 or equivalent licenses** Configures Windows diagnostic data settings for Intune. Enables features like Windows update reports, device readiness reports, and driver update reports. More information can be found in [Microsoft's documentation.](https://go.microsoft.com/fwlink/?linkid=2204384)
        (DocsDescription) Enables Windows diagnostic data in processor configuration for your Intune tenant. This setting is required for several Intune features including Windows feature update device readiness reports, compatibility risk reports, driver update reports, and update policy alerts. When enabled, your organization becomes the controller of Windows diagnostic data collected from managed devices, allowing Intune to use this data for reporting and update management features. More information can be found in [Microsoft's documentation.](https://go.microsoft.com/fwlink/?linkid=2204384)
    .NOTES
        CAT
            Intune Standards
        TAG
        EXECUTIVETEXT
            Enables access to Windows Update reporting and compatibility analysis features in Intune by allowing the use of Windows diagnostic data. This unlocks important capabilities like device readiness reports for feature updates, driver update reports, and proactive alerts for update failures, helping IT teams plan and monitor Windows updates more effectively across the organization.
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.IntuneWindowsDiagnostic.areDataProcessorServiceForWindowsFeaturesEnabled","label":"Enable Windows data","defaultValue":false}
            {"type":"switch","name":"standards.IntuneWindowsDiagnostic.hasValidWindowsLicense","label":"Confirm ownership of the required Windows E3 or equivalent licenses (Enables Windows update app and driver compatibility reports)","defaultValue":false}
        IMPACT
            Low Impact
        ADDEDDATE
            2026-01-27
        POWERSHELLEQUIVALENT
            Graph API
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    [CmdletBinding()]
    param($Tenant, $Settings)

    $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneWindowsDiagnostic' -TenantFilter $Tenant -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1')

    if ($TestResult -eq $false) {
        return $true
    }

    # Example diagnostic logic for Intune Windows devices
    try {

        $CurrentInfo = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/dataProcessorServiceForWindowsFeaturesOnboarding" -tenantid $Tenant
        $CurrentValue = $CurrentInfo | Select-Object -Property areDataProcessorServiceForWindowsFeaturesEnabled, hasValidWindowsLicense

        $StateIsCorrect = ($CurrentInfo.areDataProcessorServiceForWindowsFeaturesEnabled -eq $Settings.areDataProcessorServiceForWindowsFeaturesEnabled) -and ($CurrentInfo.hasValidWindowsLicense -eq $Settings.hasValidWindowsLicense)
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to retrieve Windows diagnostic data settings for Intune." -Sev 'Error' -LogData $ErrorMessage
        throw "Failed to retrieve current Windows diagnostic data settings for Intune. Error: $($ErrorMessage)"
    }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Windows Diagnostic for Intune is already in the desired state." -sev Info
        }
        else {
            $Body = [pscustomobject]@{
                value = @{
                    areDataProcessorServiceForWindowsFeaturesEnabled = $Settings.areDataProcessorServiceForWindowsFeaturesEnabled
                    hasValidWindowsLicense                           = $Settings.hasValidWindowsLicense
                }
            } | ConvertTo-Json -Depth 10 -Compress

            try {
                $null = New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/deviceManagement/dataProcessorServiceForWindowsFeaturesOnboarding' -Type PATCH -Body $body -ContentType 'application/json' -AsApp $true
                $CurrentInfo.areDataProcessorServiceForWindowsFeaturesEnabled = $Settings.areDataProcessorServiceForWindowsFeaturesEnabled
                $CurrentInfo.hasValidWindowsLicense = $Settings.hasValidWindowsLicense
                $StateIsCorrect = $true
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully updated Windows Diagnostic settings for Intune." -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to update Windows Diagnostic settings for Intune. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Windows Diagnostic for Intune is in the desired state." -sev Info
        } else {
            Write-StandardsAlert -message "Windows Diagnostic for Intune is not in the desired state." -object $CurrentValue -tenant $Tenant -standardName 'IntuneWindowsDiagnostic' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Windows Diagnostic for Intune is not in the desired state." -sev Info
        }

    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            areDataProcessorServiceForWindowsFeaturesEnabled = $CurrentInfo.areDataProcessorServiceForWindowsFeaturesEnabled
            hasValidWindowsLicense                           = $CurrentInfo.hasValidWindowsLicense
        }
        $ExpectedValue = @{
            areDataProcessorServiceForWindowsFeaturesEnabled = $Settings.areDataProcessorServiceForWindowsFeaturesEnabled
            hasValidWindowsLicense                           = $Settings.hasValidWindowsLicense
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.IntuneWindowsDiagnostic' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'IntuneWindowsDiagnostic' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
