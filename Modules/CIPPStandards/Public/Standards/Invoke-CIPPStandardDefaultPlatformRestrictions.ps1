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
            "CISA (MS.AAD.19.1v1)"
        EXECUTIVETEXT
            Controls which types of devices (iOS, Android, Windows, macOS) and ownership models (corporate vs. personal) can be enrolled in the company's device management system. This helps maintain security standards while supporting necessary business device types and usage scenarios.
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
        REQUIREDCAPABILITIES
            "INTUNE_A"
            "MDM_Services"
            "EMS"
            "SCCM"
            "MICROSOFTINTUNEPLAN1"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'DefaultPlatformRestrictions' -TenantFilter $Tenant -Preset Intune

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    # The default policy is identified by its id suffix, not by deviceEnrollmentConfigurationType.
    # Graph currently reports that type as either 'platformRestrictions' or 'singlePlatformRestriction'
    # for the same object depending on the filter used, and per-platform policies expose a single
    # 'platformRestriction' property instead of the per-OS ones this standard reads.
    try {
        $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?$top=999' -tenantID $Tenant -AsApp $true |
            Where-Object { $_.id -like '*_DefaultPlatformRestrictions' } |
            Select-Object -First 1 -Property id, androidForWorkRestriction, androidRestriction, iosRestriction, macOSRestriction, windowsRestriction
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DefaultPlatformRestrictions state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if (-not $CurrentState.id) {
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not find the default platform restrictions policy for $Tenant. Skipping DefaultPlatformRestrictions." -Sev Error
        return
    }

    # Unset switches arrive as $null, which never equals $false. Coerce once so the comparison is
    # stable and the remediation body serializes booleans instead of null.
    $DesiredState = [PSCustomObject]@{
        platformAndroidForWorkBlocked = [bool]$Settings.platformAndroidForWorkBlocked
        personalAndroidForWorkBlocked = [bool]$Settings.personalAndroidForWorkBlocked
        platformAndroidBlocked        = [bool]$Settings.platformAndroidBlocked
        personalAndroidBlocked        = [bool]$Settings.personalAndroidBlocked
        platformiOSBlocked            = [bool]$Settings.platformiOSBlocked
        personaliOSBlocked            = [bool]$Settings.personaliOSBlocked
        platformMacOSBlocked          = [bool]$Settings.platformMacOSBlocked
        personalMacOSBlocked          = [bool]$Settings.personalMacOSBlocked
        platformWindowsBlocked        = [bool]$Settings.platformWindowsBlocked
        personalWindowsBlocked        = [bool]$Settings.personalWindowsBlocked
    }

    $StateIsCorrect = ($CurrentState.androidForWorkRestriction.platformBlocked -eq $DesiredState.platformAndroidForWorkBlocked) -and
    ($CurrentState.androidForWorkRestriction.personalDeviceEnrollmentBlocked -eq $DesiredState.personalAndroidForWorkBlocked) -and
    ($CurrentState.androidRestriction.platformBlocked -eq $DesiredState.platformAndroidBlocked) -and
    ($CurrentState.androidRestriction.personalDeviceEnrollmentBlocked -eq $DesiredState.personalAndroidBlocked) -and
    ($CurrentState.iosRestriction.platformBlocked -eq $DesiredState.platformiOSBlocked) -and
    ($CurrentState.iosRestriction.personalDeviceEnrollmentBlocked -eq $DesiredState.personaliOSBlocked) -and
    ($CurrentState.macOSRestriction.platformBlocked -eq $DesiredState.platformMacOSBlocked) -and
    ($CurrentState.macOSRestriction.personalDeviceEnrollmentBlocked -eq $DesiredState.personalMacOSBlocked) -and
    ($CurrentState.windowsRestriction.platformBlocked -eq $DesiredState.platformWindowsBlocked) -and
    ($CurrentState.windowsRestriction.personalDeviceEnrollmentBlocked -eq $DesiredState.personalWindowsBlocked)

    $CompareField = [PSCustomObject]@{
        platformAndroidForWorkBlocked = $CurrentState.androidForWorkRestriction.platformBlocked
        personalAndroidForWorkBlocked = $CurrentState.androidForWorkRestriction.personalDeviceEnrollmentBlocked
        platformAndroidBlocked        = $CurrentState.androidRestriction.platformBlocked
        personalAndroidBlocked        = $CurrentState.androidRestriction.personalDeviceEnrollmentBlocked
        platformiOSBlocked            = $CurrentState.iosRestriction.platformBlocked
        personaliOSBlocked            = $CurrentState.iosRestriction.personalDeviceEnrollmentBlocked
        platformMacOSBlocked          = $CurrentState.macOSRestriction.platformBlocked
        personalMacOSBlocked          = $CurrentState.macOSRestriction.personalDeviceEnrollmentBlocked
        platformWindowsBlocked        = $CurrentState.windowsRestriction.platformBlocked
        personalWindowsBlocked        = $CurrentState.windowsRestriction.personalDeviceEnrollmentBlocked
    }

    $ExpectedValue = $DesiredState

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'DefaultPlatformRestrictions is already applied correctly.' -Sev Info
        } else {
            $cmdParam = @{
                tenantid    = $Tenant
                uri         = "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations/$($CurrentState.id)"
                AsApp       = $false
                Type        = 'PATCH'
                ContentType = 'application/json; charset=utf-8'
                Body        = [PSCustomObject]@{
                    '@odata.type'             = '#microsoft.graph.deviceEnrollmentPlatformRestrictionsConfiguration'
                    androidForWorkRestriction = [PSCustomObject]@{
                        '@odata.type'                   = 'microsoft.graph.deviceEnrollmentPlatformRestriction'
                        platformBlocked                 = $DesiredState.platformAndroidForWorkBlocked
                        personalDeviceEnrollmentBlocked = $DesiredState.personalAndroidForWorkBlocked
                    }
                    androidRestriction        = [PSCustomObject]@{
                        '@odata.type'                   = 'microsoft.graph.deviceEnrollmentPlatformRestriction'
                        platformBlocked                 = $DesiredState.platformAndroidBlocked
                        personalDeviceEnrollmentBlocked = $DesiredState.personalAndroidBlocked
                    }
                    iosRestriction            = [PSCustomObject]@{
                        '@odata.type'                   = 'microsoft.graph.deviceEnrollmentPlatformRestriction'
                        platformBlocked                 = $DesiredState.platformiOSBlocked
                        personalDeviceEnrollmentBlocked = $DesiredState.personaliOSBlocked
                    }
                    macOSRestriction          = [PSCustomObject]@{
                        '@odata.type'                   = 'microsoft.graph.deviceEnrollmentPlatformRestriction'
                        platformBlocked                 = $DesiredState.platformMacOSBlocked
                        personalDeviceEnrollmentBlocked = $DesiredState.personalMacOSBlocked
                    }
                    windowsRestriction        = [PSCustomObject]@{
                        '@odata.type'                   = 'microsoft.graph.deviceEnrollmentPlatformRestriction'
                        platformBlocked                 = $DesiredState.platformWindowsBlocked
                        personalDeviceEnrollmentBlocked = $DesiredState.personalWindowsBlocked
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

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'DefaultPlatformRestrictions is correctly set.' -Sev Info
        } else {
            Write-StandardsAlert -message 'DefaultPlatformRestrictions is incorrectly set.' -object $CompareField -tenant $Tenant -standardName 'DefaultPlatformRestrictions' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'DefaultPlatformRestrictions is incorrectly set.' -Sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.DefaultPlatformRestrictions' -CurrentValue $CompareField -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DefaultPlatformRestrictions' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
