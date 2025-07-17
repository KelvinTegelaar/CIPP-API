function Invoke-CIPPStandardDefaultPlatformRestrictions {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DefaultPlatformRestrictions
    .SYNOPSIS
        (Label) Device enrollment restrictions
    .DESCRIPTION
        (Helptext) Sets the default platform restrictions for enrolling devices into Intune. Note: Do not block personally owned if platform is blocked.
        (DocsDescription) Sets the default platform restrictions for enrolling devices into Intune. Note: Do not block personally owned if platform is blocked.
    .NOTES
        CAT
            Intune Standards
        TAG
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.DefaultPlatformRestrictions.platformAndroidForWorkBlocked","label":"Block platform Android Enterprise (work profile)","default":false}
            {"type":"switch","name":"standards.DefaultPlatformRestrictions.personalAndroidForWorkBlocked","label":"Block personally owned Android Enterprise (work profile)","default":false}
            {"type":"switch","name":"standards.DefaultPlatformRestrictions.platformAndroidBlocked","label":"Block platform Android","default":false}
            {"type":"switch","name":"standards.DefaultPlatformRestrictions.personalAndroidBlocked","label":"Block personally owned Android","default":false}
            {"type":"switch","name":"standards.DefaultPlatformRestrictions.platformiOSBlocked","label":"Block platform iOS","default":false}
            {"type":"switch","name":"standards.DefaultPlatformRestrictions.personaliOSBlocked","label":"Block personally owned iOS","default":false}
            {"type":"switch","name":"standards.DefaultPlatformRestrictions.platformMacOSBlocked","label":"Block platform macOS","default":false}
            {"type":"switch","name":"standards.DefaultPlatformRestrictions.personalMacOSBlocked","label":"Block personally owned macOS","default":false}
            {"type":"switch","name":"standards.DefaultPlatformRestrictions.platformWindowsBlocked","label":"Block platform Windows","default":false}
            {"type":"switch","name":"standards.DefaultPlatformRestrictions.personalWindowsBlocked","label":"Block personally owned Windows","default":false}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-04-01
        POWERSHELLEQUIVALENT
            Graph API
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'DefaultPlatformRestrictions' -TenantFilter $Tenant -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1')

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    try {
        $CurrentState = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?`$expand=assignments&orderBy=priority&`$filter=deviceEnrollmentConfigurationType eq 'SinglePlatformRestriction'" -tenantID $Tenant -AsApp $true |
        Select-Object -Property id, androidForWorkRestriction, androidRestriction, iosRestriction, macOSRestriction, windowsRestriction
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DefaultPlatformRestrictions for $Tenant. This tenant might not have premium licenses available: $ErrorMessage" -Sev Error
    }

    $StateIsCorrect = ($CurrentState.androidForWorkRestriction.platformBlocked -eq $Settings.platformAndroidForWorkBlocked) -and
        ($CurrentState.androidForWorkRestriction.personalDeviceEnrollmentBlocked -eq $Settings.personalAndroidForWorkBlocked) -and
        ($CurrentState.androidRestriction.platformBlocked -eq $Settings.platformAndroidBlocked) -and
        ($CurrentState.androidRestriction.personalDeviceEnrollmentBlocked -eq $Settings.personalAndroidBlocked) -and
        ($CurrentState.iosRestriction.platformBlocked -eq $Settings.platformiOSBlocked) -and
        ($CurrentState.iosRestriction.personalDeviceEnrollmentBlocked -eq $Settings.personaliOSBlocked) -and
        ($CurrentState.macOSRestriction.platformBlocked -eq $Settings.platformMacOSBlocked) -and
        ($CurrentState.macOSRestriction.personalDeviceEnrollmentBlocked -eq $Settings.personalMacOSBlocked) -and
        ($CurrentState.windowsRestriction.platformBlocked -eq $Settings.platformWindowsBlocked) -and
        ($CurrentState.windowsRestriction.personalDeviceEnrollmentBlocked -eq $Settings.personalWindowsBlocked)

    $CompareField = [PSCustomObject]@{
        platformAndroidForWorkBlocked   = $CurrentState.androidForWorkRestriction.platformBlocked
        personalAndroidForWorkBlocked   = $CurrentState.androidForWorkRestriction.personalDeviceEnrollmentBlocked
        platformAndroidBlocked          = $CurrentState.androidRestriction.platformBlocked
        personalAndroidBlocked          = $CurrentState.androidRestriction.personalDeviceEnrollmentBlocked
        platformiOSBlocked              = $CurrentState.iosRestriction.platformBlocked
        personaliOSBlocked              = $CurrentState.iosRestriction.personalDeviceEnrollmentBlocked
        platformMacOSBlocked            = $CurrentState.macOSRestriction.platformBlocked
        personalMacOSBlocked            = $CurrentState.macOSRestriction.personalDeviceEnrollmentBlocked
        platformWindowsBlocked          = $CurrentState.windowsRestriction.platformBlocked
        personalWindowsBlocked          = $CurrentState.windowsRestriction.personalDeviceEnrollmentBlocked
    }

    If ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'DefaultPlatformRestrictions is already applied correctly.' -Sev Info
        } else {
            $cmdParam = @{
                tenantid  = $Tenant
                uri      = "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations/$($CurrentState.id)"
                AsApp    = $false
                Type     = 'PATCH'
                ContentType = 'application/json; charset=utf-8'
                Body     = [PSCustomObject]@{
                    "@odata.type" = "#microsoft.graph.deviceEnrollmentPlatformRestrictionsConfiguration"
                    androidForWorkRestriction = [PSCustomObject]@{
                        "@odata.type"                   = "microsoft.graph.deviceEnrollmentPlatformRestriction"
                        platformBlocked                 = $Settings.platformAndroidForWorkBlocked
                        personalDeviceEnrollmentBlocked = $Settings.personalAndroidForWorkBlocked
                    }
                    androidRestriction = [PSCustomObject]@{
                        "@odata.type"                   = "microsoft.graph.deviceEnrollmentPlatformRestriction"
                        platformBlocked                 = $Settings.platformAndroidBlocked
                        personalDeviceEnrollmentBlocked = $Settings.personalAndroidBlocked
                    }
                    iosRestriction = [PSCustomObject]@{
                        "@odata.type"                   = "microsoft.graph.deviceEnrollmentPlatformRestriction"
                        platformBlocked                 = $Settings.platformiOSBlocked
                        personalDeviceEnrollmentBlocked = $Settings.personaliOSBlocked
                    }
                    macOSRestriction = [PSCustomObject]@{
                        "@odata.type"                   = "microsoft.graph.deviceEnrollmentPlatformRestriction"
                        platformBlocked                 = $Settings.platformMacOSBlocked
                        personalDeviceEnrollmentBlocked = $Settings.personalMacOSBlocked
                    }
                    windowsRestriction = [PSCustomObject]@{
                        "@odata.type"                   = "microsoft.graph.deviceEnrollmentPlatformRestriction"
                        platformBlocked                 = $Settings.platformWindowsBlocked
                        personalDeviceEnrollmentBlocked = $Settings.personalWindowsBlocked
                    }
                } | ConvertTo-Json -Compress -Depth 10
            }
            try {
                $null = New-GraphPostRequest @cmdParam
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully updated DefaultPlatformRestrictions.' -Sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to update DefaultPlatformRestrictions. Error: $($ErrorMessage.NormalizedError)" -Sev Error
            }
        }

    }

    If ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'DefaultPlatformRestrictions is correctly set.' -Sev Info
        } else {
            Write-StandardsAlert -message 'DefaultPlatformRestrictions is incorrectly set.' -object $CompareField -tenant $Tenant -standardName 'DefaultPlatformRestrictions' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'DefaultPlatformRestrictions is incorrectly set.' -Sev Info
        }
    }

    If ($Settings.report -eq $true) {
        $FieldValue = $StateIsCorrect ? $true : $CompareField
        Set-CIPPStandardsCompareField -FieldName 'standards.DefaultPlatformRestrictions' -FieldValue $FieldValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DefaultPlatformRestrictions' -FieldValue [bool]$StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
