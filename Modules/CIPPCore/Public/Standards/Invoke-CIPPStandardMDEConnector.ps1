function Invoke-CIPPStandardMDEConnector {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) MDEConnector
    .SYNOPSIS
        (Label) Microsoft Defender for Endpoint Connector Settings
    .DESCRIPTION
        (Helptext) Configures the Microsoft Defender for Endpoint (MDE) Intune connector settings, including compliance policy evaluation connectors for Android, iOS/iPadOS, and Windows devices, app sync, certificate sync, app protection policy evaluation, unsupported OS blocking, and the partner unresponsiveness threshold.
        (DocsDescription) Configures the Microsoft Defender for Endpoint (MDE) Intune connector. This covers the "Endpoint Security Profile Settings" (allowing MDE to enforce endpoint security configurations), all "Compliance policy evaluation" toggles (Android 6.0+, iOS/iPadOS 13.0+, Windows 10.0.15063+), iOS App Sync, iOS Certificate Sync, "Block unsupported OS versions", and "App protection policy evaluation" connectors for Android and iOS. Also sets the shared "Number of days until partner is unresponsive" threshold.
    .NOTES
    CAT
        Intune Standards
    TAG
        "CIS"
        "MDE"
    EXECUTIVETEXT
        Ensures the Microsoft Defender for Endpoint connector is properly configured in Microsoft Intune. This enables device risk signals from MDE to flow into Intune compliance and app protection policies across Android, iOS/iPadOS, and Windows platforms, strengthening the organisation's Zero Trust posture.
    ADDEDCOMPONENT
        {"type": "heading", "label": "Endpoint Security Profile Settings"}
        {"type": "switch", "name": "standards.MDEConnector.microsoftDefenderForEndpointAttachEnabled", "label": "Allow Microsoft Defender for Endpoint to enforce Endpoint Security Configurations", "default": true}
        {"type": "heading", "label": "Compliance policy evaluation"}
        {"type": "switch", "name": "standards.MDEConnector.androidEnabled", "label": "Connect Android devices version 6.0+ to Microsoft Defender for Endpoint", "default": true}
        {"type": "switch", "name": "standards.MDEConnector.iosEnabled", "label": "Connect iOS/iPadOS devices version 13.0+ to Microsoft Defender for Endpoint", "default": true}
        {"type": "switch", "name": "standards.MDEConnector.windowsEnabled", "label": "Connect Windows devices version 10.0.15063+ to Microsoft Defender for Endpoint", "default": true}
        {"type": "switch", "name": "standards.MDEConnector.macEnabled", "label": "Connect macOS devices to Microsoft Defender for Endpoint", "default": false}
        {"type": "switch", "name": "standards.MDEConnector.allowPartnerToCollectIOSApplicationMetadata", "label": "Enable App Sync (send application inventory) for iOS/iPadOS devices", "default": true}
        {"type": "switch", "name": "standards.MDEConnector.allowPartnerToCollectIOSPersonalApplicationMetadata", "label": "Send full application inventory data on personally owned iOS/iPadOS devices", "default": false}
        {"type": "switch", "name": "standards.MDEConnector.allowPartnerToCollectIosCertificateMetadata", "label": "Enable Certificate Sync for iOS/iPadOS devices", "default": true}
        {"type": "switch", "name": "standards.MDEConnector.allowPartnerToCollectIosPersonalCertificateMetadata", "label": "Send full certificate inventory data on personally owned iOS/iPadOS devices", "default": false}
        {"type": "switch", "name": "standards.MDEConnector.partnerUnsupportedOsVersionBlocked", "label": "Block unsupported OS versions", "default": true}
        {"type": "heading", "label": "App protection policy evaluation"}
        {"type": "switch", "name": "standards.MDEConnector.androidMobileApplicationManagementEnabled", "label": "Connect Android devices to Microsoft Defender for Endpoint (App Protection Policy)", "default": false}
        {"type": "switch", "name": "standards.MDEConnector.iosMobileApplicationManagementEnabled", "label": "Connect iOS/iPadOS devices to Microsoft Defender for Endpoint (App Protection Policy)", "default": false}
        {"type": "heading", "label": "Shared settings"}
        {"type": "number", "name": "standards.MDEConnector.partnerUnresponsivenessThresholdInDays", "label": "Number of days until partner is unresponsive (1-90)", "default": 7}
    IMPACT
        Medium Impact
    ADDEDDATE
        2026-03-22
    POWERSHELLEQUIVALENT
        Graph API - PATCH /beta/deviceManagement/mobileThreatDefenseConnectors/fc780465-2017-40d4-a0c5-307022471b92
    RECOMMENDEDBY
        "CIS"
        "CISA"
    UPDATECOMMENTBLOCK
        Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    $TestResult = Test-CIPPStandardLicense -StandardName 'MDEConnector' -TenantFilter $Tenant -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'MICROSOFTINTUNEPLAN1', 'ATP', 'MDATP', 'WIN_DEF_ATP')

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    $ConnectorId = 'fc780465-2017-40d4-a0c5-307022471b92'
    $ConnectorUri = "https://graph.microsoft.com/beta/deviceManagement/mobileThreatDefenseConnectors/$ConnectorId"

    $appSyncEnabled    = [bool]$Settings.allowPartnerToCollectIOSApplicationMetadata
    $appSyncPersonal   = if ($appSyncEnabled) { [bool]$Settings.allowPartnerToCollectIOSPersonalApplicationMetadata } else { $false }

    $certSyncEnabled   = [bool]$Settings.allowPartnerToCollectIosCertificateMetadata
    $certSyncPersonal  = if ($certSyncEnabled) { [bool]$Settings.allowPartnerToCollectIosPersonalCertificateMetadata } else { $false }

    $DesiredState = [PSCustomObject]@{
        id                                               = $ConnectorId
        microsoftDefenderForEndpointAttachEnabled        = [bool]$Settings.microsoftDefenderForEndpointAttachEnabled
        androidEnabled                                   = [bool]$Settings.androidEnabled
        iosEnabled                                       = [bool]$Settings.iosEnabled
        windowsEnabled                                   = [bool]$Settings.windowsEnabled
        macEnabled                                       = [bool]$Settings.macEnabled
        allowPartnerToCollectIOSApplicationMetadata      = $appSyncEnabled
        allowPartnerToCollectIOSPersonalApplicationMetadata = $appSyncPersonal
        allowPartnerToCollectIosCertificateMetadata      = $certSyncEnabled
        allowPartnerToCollectIosPersonalCertificateMetadata = $certSyncPersonal
        partnerUnsupportedOsVersionBlocked               = [bool]$Settings.partnerUnsupportedOsVersionBlocked
        androidMobileApplicationManagementEnabled        = [bool]$Settings.androidMobileApplicationManagementEnabled
        iosMobileApplicationManagementEnabled            = [bool]$Settings.iosMobileApplicationManagementEnabled
        partnerUnresponsivenessThresholdInDays           = [int]($Settings.partnerUnresponsivenessThresholdInDays ?? 7)
    }

    $ConnectorExists = $false
    $CurrentState    = $null

    try {
        $CurrentState    = New-GraphGetRequest -uri $ConnectorUri -tenantid $Tenant -AsApp $true
        $ConnectorExists = $true
    } catch {
        $ConnectorExists = $false
    }

    $StateIsCorrect = $false
    if ($ConnectorExists -and $null -ne $CurrentState) {
        $StateIsCorrect = (
            $CurrentState.microsoftDefenderForEndpointAttachEnabled        -eq $DesiredState.microsoftDefenderForEndpointAttachEnabled        -and
            $CurrentState.androidEnabled                                   -eq $DesiredState.androidEnabled                                   -and
            $CurrentState.iosEnabled                                       -eq $DesiredState.iosEnabled                                       -and
            $CurrentState.windowsEnabled                                   -eq $DesiredState.windowsEnabled                                   -and
            $CurrentState.macEnabled                                       -eq $DesiredState.macEnabled                                       -and
            $CurrentState.allowPartnerToCollectIOSApplicationMetadata      -eq $DesiredState.allowPartnerToCollectIOSApplicationMetadata      -and
            $CurrentState.allowPartnerToCollectIOSPersonalApplicationMetadata -eq $DesiredState.allowPartnerToCollectIOSPersonalApplicationMetadata -and
            $CurrentState.allowPartnerToCollectIosCertificateMetadata      -eq $DesiredState.allowPartnerToCollectIosCertificateMetadata      -and
            $CurrentState.allowPartnerToCollectIosPersonalCertificateMetadata -eq $DesiredState.allowPartnerToCollectIosPersonalCertificateMetadata -and
            $CurrentState.partnerUnsupportedOsVersionBlocked               -eq $DesiredState.partnerUnsupportedOsVersionBlocked               -and
            $CurrentState.androidMobileApplicationManagementEnabled        -eq $DesiredState.androidMobileApplicationManagementEnabled        -and
            $CurrentState.iosMobileApplicationManagementEnabled            -eq $DesiredState.iosMobileApplicationManagementEnabled            -and
            $CurrentState.partnerUnresponsivenessThresholdInDays           -eq $DesiredState.partnerUnresponsivenessThresholdInDays
        )
    }

    $CompareField = [PSCustomObject]@{
        microsoftDefenderForEndpointAttachEnabled           = $CurrentState.microsoftDefenderForEndpointAttachEnabled
        androidEnabled                                      = $CurrentState.androidEnabled
        iosEnabled                                          = $CurrentState.iosEnabled
        windowsEnabled                                      = $CurrentState.windowsEnabled
        macEnabled                                          = $CurrentState.macEnabled
        allowPartnerToCollectIOSApplicationMetadata         = $CurrentState.allowPartnerToCollectIOSApplicationMetadata
        allowPartnerToCollectIOSPersonalApplicationMetadata = $CurrentState.allowPartnerToCollectIOSPersonalApplicationMetadata
        allowPartnerToCollectIosCertificateMetadata         = $CurrentState.allowPartnerToCollectIosCertificateMetadata
        allowPartnerToCollectIosPersonalCertificateMetadata = $CurrentState.allowPartnerToCollectIosPersonalCertificateMetadata
        partnerUnsupportedOsVersionBlocked                  = $CurrentState.partnerUnsupportedOsVersionBlocked
        androidMobileApplicationManagementEnabled           = $CurrentState.androidMobileApplicationManagementEnabled
        iosMobileApplicationManagementEnabled               = $CurrentState.iosMobileApplicationManagementEnabled
        partnerUnresponsivenessThresholdInDays              = $CurrentState.partnerUnresponsivenessThresholdInDays
    }

    $ExpectedValue = [PSCustomObject]@{
        microsoftDefenderForEndpointAttachEnabled           = $DesiredState.microsoftDefenderForEndpointAttachEnabled
        androidEnabled                                      = $DesiredState.androidEnabled
        iosEnabled                                          = $DesiredState.iosEnabled
        windowsEnabled                                      = $DesiredState.windowsEnabled
        macEnabled                                          = $DesiredState.macEnabled
        allowPartnerToCollectIOSApplicationMetadata         = $DesiredState.allowPartnerToCollectIOSApplicationMetadata
        allowPartnerToCollectIOSPersonalApplicationMetadata = $DesiredState.allowPartnerToCollectIOSPersonalApplicationMetadata
        allowPartnerToCollectIosCertificateMetadata         = $DesiredState.allowPartnerToCollectIosCertificateMetadata
        allowPartnerToCollectIosPersonalCertificateMetadata = $DesiredState.allowPartnerToCollectIosPersonalCertificateMetadata
        partnerUnsupportedOsVersionBlocked                  = $DesiredState.partnerUnsupportedOsVersionBlocked
        androidMobileApplicationManagementEnabled           = $DesiredState.androidMobileApplicationManagementEnabled
        iosMobileApplicationManagementEnabled               = $DesiredState.iosMobileApplicationManagementEnabled
        partnerUnresponsivenessThresholdInDays              = $DesiredState.partnerUnresponsivenessThresholdInDays
    }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'MDEConnector settings are already correctly configured.' -Sev Info
        } else {
            $Body = $DesiredState | ConvertTo-Json -Compress -Depth 5

            try {
                if ($ConnectorExists) {
                    $null = New-GraphPostRequest -uri $ConnectorUri -tenantid $Tenant -type PATCH -body $Body -AsApp $true
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully updated MDE Connector settings.' -Sev Info
                } else {
                    $null = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/mobileThreatDefenseConnectors/' -tenantid $Tenant -type POST -body $Body -AsApp $true
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully created MDE Connector settings.' -Sev Info
                }
                $CompareField   = $ExpectedValue
                $StateIsCorrect = $true
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to configure MDE Connector settings. Error: $($ErrorMessage.NormalizedError)" -Sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'MDEConnector settings are correctly configured.' -Sev Info
        } else {
            Write-StandardsAlert -message 'MDEConnector settings are incorrectly configured.' -object $CompareField -tenant $Tenant -standardName 'MDEConnector' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'MDEConnector settings are incorrectly configured.' -Sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.MDEConnector' -CurrentValue $CompareField -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'MDEConnector' -FieldValue [bool]$StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
