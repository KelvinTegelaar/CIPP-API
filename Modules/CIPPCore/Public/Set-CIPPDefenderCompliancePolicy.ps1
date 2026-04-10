function Set-CIPPDefenderCompliancePolicy {
    <#
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$TenantFilter,
        $Compliance,
        $Headers,
        [string]$APIName
    )

    $ConnectorStatus = Enable-CIPPMDEConnector -TenantFilter $TenantFilter
    if (!$ConnectorStatus.Success) {
        "$($TenantFilter): Failed to enable MDE Connector - $($ConnectorStatus.ErrorMessage)"
        return
    } else {
        "$($TenantFilter): MDE Connector is $($ConnectorStatus.PartnerState)"
    }

    $SettingsObject = @{
        id                                                  = 'fc780465-2017-40d4-a0c5-307022471b92'
        androidEnabled                                      = [bool]$Compliance.ConnectAndroid
        iosEnabled                                          = [bool]$Compliance.ConnectIos
        windowsEnabled                                      = [bool]$Compliance.Connectwindows
        macEnabled                                          = [bool]$Compliance.ConnectMac
        partnerUnsupportedOsVersionBlocked                  = [bool]$Compliance.BlockunsupportedOS
        partnerUnresponsivenessThresholdInDays              = 7
        allowPartnerToCollectIOSApplicationMetadata         = [bool]$Compliance.ConnectIosCompliance
        allowPartnerToCollectIOSPersonalApplicationMetadata = [bool]$Compliance.ConnectIosCompliance
        androidDeviceBlockedOnMissingPartnerData            = [bool]$Compliance.androidDeviceBlockedOnMissingPartnerData
        iosDeviceBlockedOnMissingPartnerData                = [bool]$Compliance.iosDeviceBlockedOnMissingPartnerData
        windowsDeviceBlockedOnMissingPartnerData            = [bool]$Compliance.windowsDeviceBlockedOnMissingPartnerData
        macDeviceBlockedOnMissingPartnerData                = [bool]$Compliance.macDeviceBlockedOnMissingPartnerData
        androidMobileApplicationManagementEnabled           = [bool]$Compliance.ConnectAndroidCompliance
        iosMobileApplicationManagementEnabled               = [bool]$Compliance.appSync
        windowsMobileApplicationManagementEnabled           = [bool]$Compliance.windowsMobileApplicationManagementEnabled
        allowPartnerToCollectIosCertificateMetadata         = [bool]$Compliance.allowPartnerToCollectIosCertificateMetadata
        allowPartnerToCollectIosPersonalCertificateMetadata = [bool]$Compliance.allowPartnerToCollectIosPersonalCertificateMetadata
        microsoftDefenderForEndpointAttachEnabled           = [bool]$true
    }
    $SettingsObj = $SettingsObject | ConvertTo-Json -Compress
    $ConnectorUri = 'https://graph.microsoft.com/beta/deviceManagement/mobileThreatDefenseConnectors/fc780465-2017-40d4-a0c5-307022471b92'
    $ConnectorExists = $false
    $SettingsMatch = $false
    try {
        $ExistingSettings = New-GraphGETRequest -uri $ConnectorUri -tenantid $TenantFilter
        $ConnectorExists = $true

        $SettingsMatch = $true
        foreach ($key in $SettingsObject.Keys) {
            if ($ExistingSettings.$key -ne $SettingsObject[$key]) {
                $SettingsMatch = $false
                break
            }
        }
    } catch {
        $ConnectorExists = $false
    }

    if ($SettingsMatch) {
        "Defender Intune Configuration already correct and active for $($TenantFilter). Skipping"
    } elseif ($ConnectorExists) {
        $null = New-GraphPOSTRequest -uri $ConnectorUri -tenantid $TenantFilter -type PATCH -body $SettingsObj -AsApp $true
        "$($TenantFilter): Successfully updated Defender Compliance and Reporting settings."
    } else {
        $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/mobileThreatDefenseConnectors/' -tenantid $TenantFilter -type POST -body $SettingsObj -AsApp $true
        "$($TenantFilter): Successfully created Defender Compliance and Reporting settings."
    }
}
