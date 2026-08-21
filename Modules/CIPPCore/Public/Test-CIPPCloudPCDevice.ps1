function Test-CIPPCloudPCDevice {
    <#
    .SYNOPSIS
        Returns whether an Intune managed device is a Windows 365 Cloud PC

    .DESCRIPTION
        Cloud PCs never report BitLocker (isEncrypted stays false) although their disks are
        encrypted at rest by Azure platform/storage encryption, so encryption reporting must
        treat them as platform-encrypted instead of flagging them as unencrypted.

        deviceType 'cloudPC' is the documented Graph signal; the model/manufacturer pair
        Windows 365 provisions ("Cloud PC ..." / "Microsoft Corporation") covers responses
        where deviceType is missing. chassisType has no cloudPC member in current Graph
        metadata but is checked anyway in case the service starts emitting it. The default
        "CPC-" device-name prefix is deliberately NOT used - names are user-controllable.

    .PARAMETER Device
        The managedDevice object (raw Graph response or CIPP-cached row) to test
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Device
    )

    if ($Device.isCloudPC -eq $true) { return $true }
    if ($Device.deviceType -eq 'cloudPC' -or $Device.chassisType -eq 'cloudPC') { return $true }
    return [bool]($Device.model -like 'Cloud PC*' -and $Device.manufacturer -eq 'Microsoft Corporation')
}
