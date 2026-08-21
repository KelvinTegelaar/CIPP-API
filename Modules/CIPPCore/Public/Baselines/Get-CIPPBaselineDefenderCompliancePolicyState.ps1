function Get-CIPPBaselineDefenderCompliancePolicyState {
    <#
    .SYNOPSIS
        Prepare hook for DefenderCompliancePolicy: the MDE mobile threat defense connector.
    .DESCRIPTION
        Reads the MDE connector singleton (fc780465-2017-40d4-a0c5-307022471b92) LIVE - it is
        one small object with no cache, exactly what the classic read. A missing connector
        grades every surface false. Two of the classic's rules are load-bearing:
        connecting Windows forces the Windows partner-data block on (Microsoft enforces it
        server-side), and microsoftDefenderForEndpointAttachEnabled always grades true.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $ConnectorState = $null
    try {
        $ConnectorState = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/mobileThreatDefenseConnectors/fc780465-2017-40d4-a0c5-307022471b92' -tenantid $TenantFilter
    } catch {
        # Connector does not exist yet - every current surface reads false below.
    }

    $V = $Item.Variables
    $Keys = @(
        'androidEnabled', 'iosEnabled', 'windowsEnabled', 'macEnabled', 'partnerUnsupportedOsVersionBlocked'
        'allowPartnerToCollectIOSApplicationMetadata', 'allowPartnerToCollectIOSPersonalApplicationMetadata'
        'androidDeviceBlockedOnMissingPartnerData', 'iosDeviceBlockedOnMissingPartnerData'
        'windowsDeviceBlockedOnMissingPartnerData', 'macDeviceBlockedOnMissingPartnerData'
        'androidMobileApplicationManagementEnabled', 'iosMobileApplicationManagementEnabled'
        'windowsMobileApplicationManagementEnabled', 'allowPartnerToCollectIosCertificateMetadata'
        'allowPartnerToCollectIosPersonalCertificateMetadata', 'grantMobileThreatDefensePartnerRole'
        'microsoftDefenderForEndpointAttachEnabled'
    )
    $Expected = [PSCustomObject]@{
        androidEnabled                                      = [bool]$V.ConnectAndroid
        iosEnabled                                          = [bool]$V.ConnectIos
        windowsEnabled                                      = [bool]$V.ConnectWindows
        macEnabled                                          = [bool]$V.ConnectMac
        partnerUnsupportedOsVersionBlocked                  = [bool]$V.BlockunsupportedOS
        allowPartnerToCollectIOSApplicationMetadata         = [bool]$V.appSync
        allowPartnerToCollectIOSPersonalApplicationMetadata = [bool]$V.allowPartnerToCollectIosPersonalApplicationMetadata
        androidDeviceBlockedOnMissingPartnerData            = [bool]$V.androidDeviceBlockedOnMissingPartnerData
        iosDeviceBlockedOnMissingPartnerData                = [bool]$V.iosDeviceBlockedOnMissingPartnerData
        windowsDeviceBlockedOnMissingPartnerData            = $(if ([bool]$V.ConnectWindows) { $true } else { [bool]$V.windowsDeviceBlockedOnMissingPartnerData })
        macDeviceBlockedOnMissingPartnerData                = [bool]$V.macDeviceBlockedOnMissingPartnerData
        androidMobileApplicationManagementEnabled           = [bool]$V.ConnectAndroidCompliance
        iosMobileApplicationManagementEnabled               = [bool]$V.ConnectIosCompliance
        windowsMobileApplicationManagementEnabled           = [bool]$V.windowsMobileApplicationManagementEnabled
        allowPartnerToCollectIosCertificateMetadata         = [bool]$V.allowPartnerToCollectIosCertificateMetadata
        allowPartnerToCollectIosPersonalCertificateMetadata = [bool]$V.allowPartnerToCollectIosPersonalCertificateMetadata
        grantMobileThreatDefensePartnerRole                 = [bool]$V.grantMobileThreatDefensePartnerRole
        microsoftDefenderForEndpointAttachEnabled           = $true
    }
    $Current = [PSCustomObject]@{}
    foreach ($Key in $Keys) {
        $Current | Add-Member -NotePropertyName $Key -NotePropertyValue ([bool]$ConnectorState.$Key)
    }
    # Carried for the executor.
    $Current | Add-Member -NotePropertyName 'connectorExists' -NotePropertyValue ($null -ne $ConnectorState)

    @{ Expected = $Expected; Current = $Current }
}
