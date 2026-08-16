function Invoke-CIPPBaselineDefenderCompliancePolicy {
    <#
    .SYNOPSIS
        DefenderCompliancePolicy executor: writes the MDE connector settings.
    .DESCRIPTION
        The classic's write: enable the MDE connector first (nothing else can succeed without
        it), then PATCH the existing connector or POST a new one carrying the FULL settings
        object - the connector endpoint replaces state, not merges it. App-only, as the
        classic wrote it.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $ConnectorStatus = Enable-CIPPMDEConnector -TenantFilter $TenantFilter
    if (-not $ConnectorStatus.Success) {
        throw "Failed to enable the MDE connector: $($ConnectorStatus.ErrorMessage)"
    }

    $ConnectWindows = [bool]$Remediate.connectWindows
    $SettingsObj = @{
        id                                                  = 'fc780465-2017-40d4-a0c5-307022471b92'
        partnerUnresponsivenessThresholdInDays              = 7
        androidEnabled                                      = [bool]$Remediate.connectAndroid
        iosEnabled                                          = [bool]$Remediate.connectIos
        windowsEnabled                                      = $ConnectWindows
        macEnabled                                          = [bool]$Remediate.connectMac
        partnerUnsupportedOsVersionBlocked                  = [bool]$Remediate.blockUnsupportedOS
        allowPartnerToCollectIOSApplicationMetadata         = [bool]$Remediate.appSync
        allowPartnerToCollectIOSPersonalApplicationMetadata = [bool]$Remediate.allowPartnerToCollectIosPersonalApplicationMetadata
        androidDeviceBlockedOnMissingPartnerData            = [bool]$Remediate.androidDeviceBlockedOnMissingPartnerData
        iosDeviceBlockedOnMissingPartnerData                = [bool]$Remediate.iosDeviceBlockedOnMissingPartnerData
        windowsDeviceBlockedOnMissingPartnerData            = $(if ($ConnectWindows) { $true } else { [bool]$Remediate.windowsDeviceBlockedOnMissingPartnerData })
        macDeviceBlockedOnMissingPartnerData                = [bool]$Remediate.macDeviceBlockedOnMissingPartnerData
        androidMobileApplicationManagementEnabled           = [bool]$Remediate.connectAndroidCompliance
        iosMobileApplicationManagementEnabled               = [bool]$Remediate.connectIosCompliance
        windowsMobileApplicationManagementEnabled           = [bool]$Remediate.windowsMobileApplicationManagementEnabled
        allowPartnerToCollectIosCertificateMetadata         = [bool]$Remediate.allowPartnerToCollectIosCertificateMetadata
        allowPartnerToCollectIosPersonalCertificateMetadata = [bool]$Remediate.allowPartnerToCollectIosPersonalCertificateMetadata
        grantMobileThreatDefensePartnerRole                 = [bool]$Remediate.grantMobileThreatDefensePartnerRole
        microsoftDefenderForEndpointAttachEnabled           = $true
    }
    $Body = $SettingsObj | ConvertTo-Json -Compress

    if ($Current.connectorExists) {
        $null = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/mobileThreatDefenseConnectors/fc780465-2017-40d4-a0c5-307022471b92' -tenantid $TenantFilter -type PATCH -body $Body -AsApp $true
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Updated the Defender compliance connector settings.' -Sev 'Info'
    } else {
        $null = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/mobileThreatDefenseConnectors/' -tenantid $TenantFilter -type POST -body $Body -AsApp $true
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Created the Defender compliance connector settings.' -Sev 'Info'
    }
}
