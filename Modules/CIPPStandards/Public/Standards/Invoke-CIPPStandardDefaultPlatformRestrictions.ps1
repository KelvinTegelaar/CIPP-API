function Invoke-CIPPStandardDefaultPlatformRestrictions {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DefaultPlatformRestrictions
    .SYNOPSIS
        (Label) Device enrollment restrictions
    .DESCRIPTION
        (Helptext) Sets the default platform restrictions for enrolling devices into Intune, including optional minimum and maximum OS version limits per platform (Android Enterprise, Android, iOS/iPadOS and Windows). Note: Do not block personally owned if platform is blocked.
        (DocsDescription) Sets the default platform restrictions for enrolling devices into Intune, including optional minimum and maximum OS version limits per platform (Android Enterprise, Android, iOS/iPadOS and Windows). Note: Do not block personally owned if platform is blocked.
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
            {"type":"textField","name":"standards.DefaultPlatformRestrictions.osMinimumVersionAndroidForWork","label":"Android Enterprise (work profile) minimum OS version","helperText":"Example: 11.0. Leave blank to not enforce a minimum.","required":false}
            {"type":"textField","name":"standards.DefaultPlatformRestrictions.osMaximumVersionAndroidForWork","label":"Android Enterprise (work profile) maximum OS version","helperText":"Example: 14.0. Leave blank to not enforce a maximum.","required":false}
            {"type":"switch","name":"standards.DefaultPlatformRestrictions.platformAndroidBlocked","label":"Block platform Android","default":false}
            {"type":"switch","name":"standards.DefaultPlatformRestrictions.personalAndroidBlocked","label":"Block personally owned Android","default":false}
            {"type":"textField","name":"standards.DefaultPlatformRestrictions.osMinimumVersionAndroid","label":"Android minimum OS version","helperText":"Example: 10.0. Leave blank to not enforce a minimum.","required":false}
            {"type":"textField","name":"standards.DefaultPlatformRestrictions.osMaximumVersionAndroid","label":"Android maximum OS version","helperText":"Example: 13.0. Leave blank to not enforce a maximum.","required":false}
            {"type":"switch","name":"standards.DefaultPlatformRestrictions.platformiOSBlocked","label":"Block platform iOS","default":false}
            {"type":"switch","name":"standards.DefaultPlatformRestrictions.personaliOSBlocked","label":"Block personally owned iOS","default":false}
            {"type":"textField","name":"standards.DefaultPlatformRestrictions.osMinimumVersioniOS","label":"iOS/iPadOS minimum OS version","helperText":"Example: 16.1. Leave blank to not enforce a minimum.","required":false}
            {"type":"textField","name":"standards.DefaultPlatformRestrictions.osMaximumVersioniOS","label":"iOS/iPadOS maximum OS version","helperText":"Example: 18.0. Leave blank to not enforce a maximum.","required":false}
            {"type":"switch","name":"standards.DefaultPlatformRestrictions.platformMacOSBlocked","label":"Block platform macOS","default":false}
            {"type":"switch","name":"standards.DefaultPlatformRestrictions.personalMacOSBlocked","label":"Block personally owned macOS","default":false}
            {"type":"switch","name":"standards.DefaultPlatformRestrictions.platformWindowsBlocked","label":"Block platform Windows","default":false}
            {"type":"switch","name":"standards.DefaultPlatformRestrictions.personalWindowsBlocked","label":"Block personally owned Windows","default":false}
            {"type":"textField","name":"standards.DefaultPlatformRestrictions.osMinimumVersionWindows","label":"Windows minimum OS version","helperText":"Example: 10.0.19045.0. Leave blank to not enforce a minimum.","required":false}
            {"type":"textField","name":"standards.DefaultPlatformRestrictions.osMaximumVersionWindows","label":"Windows maximum OS version","helperText":"Example: 10.0.22631.0. Leave blank to not enforce a maximum.","required":false}
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

    # Optional minimum/maximum OS version per platform. macOS is intentionally absent - the Intune
    # enrollment restriction for macOS carries no version limit. Each is enforced ONLY when the
    # operator supplied it: a blank field means 'no opinion', so it is left out of the compare,
    # the report and the remediation body. osMinimumVersion/osMaximumVersion are free-form strings
    # on Graph, compared as strings.
    $VersionMap = @(
        @{ Setting = 'osMinimumVersionAndroidForWork'; Restriction = 'androidForWorkRestriction'; Property = 'osMinimumVersion' }
        @{ Setting = 'osMaximumVersionAndroidForWork'; Restriction = 'androidForWorkRestriction'; Property = 'osMaximumVersion' }
        @{ Setting = 'osMinimumVersionAndroid'; Restriction = 'androidRestriction'; Property = 'osMinimumVersion' }
        @{ Setting = 'osMaximumVersionAndroid'; Restriction = 'androidRestriction'; Property = 'osMaximumVersion' }
        @{ Setting = 'osMinimumVersioniOS'; Restriction = 'iosRestriction'; Property = 'osMinimumVersion' }
        @{ Setting = 'osMaximumVersioniOS'; Restriction = 'iosRestriction'; Property = 'osMaximumVersion' }
        @{ Setting = 'osMinimumVersionWindows'; Restriction = 'windowsRestriction'; Property = 'osMinimumVersion' }
        @{ Setting = 'osMaximumVersionWindows'; Restriction = 'windowsRestriction'; Property = 'osMaximumVersion' }
    )

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

    # Fold in the configured version limits: grade only the fields the operator set, and surface
    # both the desired and current value on the compare/report objects so a version drift is visible.
    foreach ($Check in $VersionMap) {
        $DesiredVersion = "$($Settings.($Check.Setting))"
        if ([string]::IsNullOrWhiteSpace($DesiredVersion)) { continue }
        $CurrentVersion = "$($CurrentState.($Check.Restriction).($Check.Property))"
        $DesiredState | Add-Member -NotePropertyName $Check.Setting -NotePropertyValue $DesiredVersion -Force
        $CompareField | Add-Member -NotePropertyName $Check.Setting -NotePropertyValue $CurrentVersion -Force
        if ($CurrentVersion -ne $DesiredVersion) { $StateIsCorrect = $false }
    }

    $ExpectedValue = $DesiredState

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'DefaultPlatformRestrictions is already applied correctly.' -Sev Info
        } else {
            $RemediationBody = [PSCustomObject]@{
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
            }
            # Only write a version limit the operator set; a blank field is left off the payload
            # so an unconfigured platform keeps whatever version limit it already has.
            foreach ($Check in $VersionMap) {
                $DesiredVersion = "$($Settings.($Check.Setting))"
                if ([string]::IsNullOrWhiteSpace($DesiredVersion)) { continue }
                $RemediationBody.($Check.Restriction) | Add-Member -NotePropertyName $Check.Property -NotePropertyValue $DesiredVersion -Force
            }
            $cmdParam = @{
                tenantid    = $Tenant
                uri         = "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations/$($CurrentState.id)"
                AsApp       = $false
                Type        = 'PATCH'
                ContentType = 'application/json; charset=utf-8'
                Body        = $RemediationBody | ConvertTo-Json -Compress -Depth 10
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
