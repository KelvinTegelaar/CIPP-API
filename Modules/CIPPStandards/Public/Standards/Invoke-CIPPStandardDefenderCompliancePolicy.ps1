function Invoke-CIPPStandardDefenderCompliancePolicy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DefenderCompliancePolicy
    .SYNOPSIS
        (Label) Defender for Endpoint - Intune Compliance Connector
    .DESCRIPTION
        (Helptext) Configures the Microsoft Defender for Endpoint connector with Intune, enabling compliance evaluation for mobile and desktop platforms (Android, iOS, macOS, Windows). Controls which platforms connect to MDE and whether devices are blocked when partner data is missing.
        (DocsDescription) Configures the Microsoft Defender for Endpoint mobile threat defense connector with Intune. This enables compliance evaluation across platforms (Android, iOS/iPadOS, macOS, Windows) and controls settings like blocking unsupported OS versions, requiring partner data for compliance, and enabling mobile application management. The connector must be enabled before platform-specific compliance policies can evaluate device risk from MDE.
    .NOTES
        CAT
            Defender Standards
        TAG
            "defender_mde_connector"
            "defender_intune_compliance"
        EXECUTIVETEXT
            Establishes the critical link between Microsoft Defender for Endpoint and Intune, enabling security risk data from MDE to be used in device compliance policies. This ensures that only devices meeting your organization's security standards can access corporate resources, providing a foundational layer of Zero Trust security across all platforms.
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.DefenderCompliancePolicy.ConnectAndroid","label":"Connect Android devices to MDE","defaultValue":false}
            {"type":"switch","name":"standards.DefenderCompliancePolicy.ConnectAndroidCompliance","label":"Connect Android 6.0.0+ (App-based MAM)","defaultValue":false}
            {"type":"switch","name":"standards.DefenderCompliancePolicy.androidDeviceBlockedOnMissingPartnerData","label":"Block Android if partner data unavailable","defaultValue":false}
            {"type":"switch","name":"standards.DefenderCompliancePolicy.grantMobileThreatDefensePartnerRole","label":"Grant MTD role to MDE on enrolled Android COBO/COPE devices","defaultValue":false}
            {"type":"switch","name":"standards.DefenderCompliancePolicy.ConnectIos","label":"Connect iOS/iPadOS devices to MDE","defaultValue":false}
            {"type":"switch","name":"standards.DefenderCompliancePolicy.ConnectIosCompliance","label":"Connect iOS/iPadOS devices for app protection policy evaluation (MAM)","defaultValue":false}
            {"type":"switch","name":"standards.DefenderCompliancePolicy.appSync","label":"Enable App Sync (sending application inventory) for iOS/iPadOS devices","defaultValue":false}
            {"type":"switch","name":"standards.DefenderCompliancePolicy.allowPartnerToCollectIosPersonalApplicationMetadata","label":"Send full application inventory data on personally-owned iOS/iPadOS devices","defaultValue":false}
            {"type":"switch","name":"standards.DefenderCompliancePolicy.iosDeviceBlockedOnMissingPartnerData","label":"Block iOS if partner data unavailable","defaultValue":false}
            {"type":"switch","name":"standards.DefenderCompliancePolicy.allowPartnerToCollectIosCertificateMetadata","label":"Enable Certificate Sync for iOS/iPadOS devices","defaultValue":false}
            {"type":"switch","name":"standards.DefenderCompliancePolicy.allowPartnerToCollectIosPersonalCertificateMetadata","label":"Send full certificate inventory data on personally-owned iOS/iPadOS devices","defaultValue":false}
            {"type":"switch","name":"standards.DefenderCompliancePolicy.ConnectMac","label":"Connect macOS devices to MDE","defaultValue":false}
            {"type":"switch","name":"standards.DefenderCompliancePolicy.macDeviceBlockedOnMissingPartnerData","label":"Block macOS if partner data unavailable","defaultValue":false}
            {"type":"switch","name":"standards.DefenderCompliancePolicy.ConnectWindows","label":"Connect Windows 10.0.15063+ to MDE (Note: enabling this forces 'Block Windows if partner data unavailable' to on)","defaultValue":false}
            {"type":"switch","name":"standards.DefenderCompliancePolicy.windowsMobileApplicationManagementEnabled","label":"Connect Windows (MAM)","defaultValue":false}
            {"type":"switch","name":"standards.DefenderCompliancePolicy.windowsDeviceBlockedOnMissingPartnerData","label":"Block Windows if partner data unavailable (Note: Microsoft enforces this to on when Connect Windows 10.0.15063+ to MDE is on)","defaultValue":false}
            {"type":"switch","name":"standards.DefenderCompliancePolicy.BlockunsupportedOS","label":"Block unsupported OS versions","defaultValue":false}
            {"type":"switch","name":"standards.DefenderCompliancePolicy.AllowMEMEnforceCompliance","label":"Allow MEM enforcement of compliance","defaultValue":false}
        IMPACT
            High Impact
        ADDEDDATE
            2026-04-02
        POWERSHELLEQUIVALENT
            Graph API - deviceManagement/mobileThreatDefenseConnectors
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    $ConnectorUri = 'https://graph.microsoft.com/beta/deviceManagement/mobileThreatDefenseConnectors/fc780465-2017-40d4-a0c5-307022471b92'

    # Build expected settings
    $ExpectedSettings = @{
        androidEnabled                                      = [bool]$Settings.ConnectAndroid
        iosEnabled                                          = [bool]$Settings.ConnectIos
        windowsEnabled                                      = [bool]$Settings.ConnectWindows
        macEnabled                                          = [bool]$Settings.ConnectMac
        partnerUnsupportedOsVersionBlocked                  = [bool]$Settings.BlockunsupportedOS
        allowPartnerToCollectIOSApplicationMetadata         = [bool]$Settings.appSync
        allowPartnerToCollectIOSPersonalApplicationMetadata = [bool]$Settings.allowPartnerToCollectIosPersonalApplicationMetadata
        androidDeviceBlockedOnMissingPartnerData            = [bool]$Settings.androidDeviceBlockedOnMissingPartnerData
        iosDeviceBlockedOnMissingPartnerData                = [bool]$Settings.iosDeviceBlockedOnMissingPartnerData
        windowsDeviceBlockedOnMissingPartnerData            = if ([bool]$Settings.ConnectWindows) { $true } else { [bool]$Settings.windowsDeviceBlockedOnMissingPartnerData }
        macDeviceBlockedOnMissingPartnerData                = [bool]$Settings.macDeviceBlockedOnMissingPartnerData
        androidMobileApplicationManagementEnabled           = [bool]$Settings.ConnectAndroidCompliance
        iosMobileApplicationManagementEnabled               = [bool]$Settings.ConnectIosCompliance
        windowsMobileApplicationManagementEnabled           = [bool]$Settings.windowsMobileApplicationManagementEnabled
        allowPartnerToCollectIosCertificateMetadata         = [bool]$Settings.allowPartnerToCollectIosCertificateMetadata
        allowPartnerToCollectIosPersonalCertificateMetadata = [bool]$Settings.allowPartnerToCollectIosPersonalCertificateMetadata
        grantMobileThreatDefensePartnerRole                 = [bool]$Settings.grantMobileThreatDefensePartnerRole
        microsoftDefenderForEndpointAttachEnabled           = $true
    }

    # Try to get current state
    $CurrentState = $null
    $ConnectorExists = $false
    try {
        $CurrentState = New-GraphGETRequest -uri $ConnectorUri -tenantid $Tenant
        $ConnectorExists = $true
    } catch {
        # Connector doesn't exist yet
    }

    # Compare settings
    $StateIsCorrect = $false
    if ($ConnectorExists -and $CurrentState) {
        $StateIsCorrect = $true
        foreach ($key in $ExpectedSettings.Keys) {
            if ($CurrentState.$key -ne $ExpectedSettings[$key]) {
                $StateIsCorrect = $false
                break
            }
        }
    }

    $CurrentValue = if ($CurrentState) {
        [PSCustomObject]@{
            androidEnabled                                      = [bool]$CurrentState.androidEnabled
            iosEnabled                                          = [bool]$CurrentState.iosEnabled
            windowsEnabled                                      = [bool]$CurrentState.windowsEnabled
            macEnabled                                          = [bool]$CurrentState.macEnabled
            partnerUnsupportedOsVersionBlocked                  = [bool]$CurrentState.partnerUnsupportedOsVersionBlocked
            allowPartnerToCollectIOSApplicationMetadata         = [bool]$CurrentState.allowPartnerToCollectIOSApplicationMetadata
            allowPartnerToCollectIOSPersonalApplicationMetadata = [bool]$CurrentState.allowPartnerToCollectIOSPersonalApplicationMetadata
            androidDeviceBlockedOnMissingPartnerData            = [bool]$CurrentState.androidDeviceBlockedOnMissingPartnerData
            iosDeviceBlockedOnMissingPartnerData                = [bool]$CurrentState.iosDeviceBlockedOnMissingPartnerData
            windowsDeviceBlockedOnMissingPartnerData            = [bool]$CurrentState.windowsDeviceBlockedOnMissingPartnerData
            macDeviceBlockedOnMissingPartnerData                = [bool]$CurrentState.macDeviceBlockedOnMissingPartnerData
            androidMobileApplicationManagementEnabled           = [bool]$CurrentState.androidMobileApplicationManagementEnabled
            iosMobileApplicationManagementEnabled               = [bool]$CurrentState.iosMobileApplicationManagementEnabled
            windowsMobileApplicationManagementEnabled           = [bool]$CurrentState.windowsMobileApplicationManagementEnabled
            allowPartnerToCollectIosCertificateMetadata         = [bool]$CurrentState.allowPartnerToCollectIosCertificateMetadata
            allowPartnerToCollectIosPersonalCertificateMetadata = [bool]$CurrentState.allowPartnerToCollectIosPersonalCertificateMetadata
            grantMobileThreatDefensePartnerRole                 = [bool]$CurrentState.grantMobileThreatDefensePartnerRole
            microsoftDefenderForEndpointAttachEnabled           = [bool]$CurrentState.microsoftDefenderForEndpointAttachEnabled
        }
    } else {
        [PSCustomObject]@{
            androidEnabled                                      = $false
            iosEnabled                                          = $false
            windowsEnabled                                      = $false
            macEnabled                                          = $false
            partnerUnsupportedOsVersionBlocked                  = $false
            allowPartnerToCollectIOSApplicationMetadata         = $false
            allowPartnerToCollectIOSPersonalApplicationMetadata = $false
            androidDeviceBlockedOnMissingPartnerData            = $false
            iosDeviceBlockedOnMissingPartnerData                = $false
            windowsDeviceBlockedOnMissingPartnerData            = $false
            macDeviceBlockedOnMissingPartnerData                = $false
            androidMobileApplicationManagementEnabled           = $false
            iosMobileApplicationManagementEnabled               = $false
            windowsMobileApplicationManagementEnabled           = $false
            allowPartnerToCollectIosCertificateMetadata         = $false
            allowPartnerToCollectIosPersonalCertificateMetadata = $false
            grantMobileThreatDefensePartnerRole                 = $false
            microsoftDefenderForEndpointAttachEnabled           = $false
        }
    }

    $ExpectedValue = [PSCustomObject]$ExpectedSettings

    if ($Settings.remediate -eq $true) {
        # Enable MDE connector first
        $ConnectorStatus = Enable-CIPPMDEConnector -TenantFilter $Tenant
        if (!$ConnectorStatus.Success) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable MDE Connector - $($ConnectorStatus.ErrorMessage)" -sev Error
            return
        }

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Defender Intune Compliance connector already correctly configured' -sev Info
        } else {
            try {
                $SettingsObj = @{
                    id                                     = 'fc780465-2017-40d4-a0c5-307022471b92'
                    partnerUnresponsivenessThresholdInDays = 7
                } + $ExpectedSettings
                $Body = $SettingsObj | ConvertTo-Json -Compress

                if ($ConnectorExists) {
                    $null = New-GraphPOSTRequest -uri $ConnectorUri -tenantid $Tenant -type PATCH -body $Body -AsApp $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated Defender Compliance connector settings' -sev Info
                } else {
                    $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/mobileThreatDefenseConnectors/' -tenantid $Tenant -type POST -body $Body -AsApp $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Created Defender Compliance connector settings' -sev Info
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Defender Compliance connector: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Defender Intune Compliance connector is correctly configured' -sev Info
        } else {
            Write-StandardsAlert -message 'Defender Intune Compliance connector is not correctly configured' -object $CurrentValue -tenant $Tenant -standardName 'DefenderCompliancePolicy' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Defender Intune Compliance connector is not correctly configured' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.DefenderCompliancePolicy' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DefenderCompliancePolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
