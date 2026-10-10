function Find-HuduDeviceMatch {
    <#
        .SYNOPSIS
        Finds Hudu assets that correspond to an Intune managed device.

        .DESCRIPTION
        Uses a usable serial number first and falls back to the device name. Blank
        and excluded serial numbers never participate in serial matching.
        Pass SerialIndex and NameIndex (built from Get-HuduDeviceMatchKey) when matching many devices against the
        same assets; without them the assets are indexed on each call.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Device,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$HuduDevices,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$ExcludeSerials = @(),

        [Parameter(Mandatory = $false)]
        $SerialIndex,

        [Parameter(Mandatory = $false)]
        $NameIndex
    )

    if (-not $SerialIndex -or -not $NameIndex) {
        $Keys = @(foreach ($HuduDevice in $HuduDevices) { Get-HuduDeviceMatchKey -HuduDevice $HuduDevice })
        $SerialIndex = [CIPP.CippIndex]::Build($HuduDevices, @(foreach ($Key in $Keys) { , $Key.Serial }))
        $NameIndex = [CIPP.CippIndex]::Build($HuduDevices, @(foreach ($Key in $Keys) { , $Key.Name }))
    }

    $SerialNumber = [string]$Device.serialNumber
    $DeviceName = [string]$Device.deviceName
    $SerialIsUsable = -not [string]::IsNullOrWhiteSpace($SerialNumber) -and $SerialNumber -notin $ExcludeSerials

    if ($SerialIsUsable) {
        $SerialMatches = @($SerialIndex.Find($SerialNumber))
        if ($SerialMatches.Count -gt 0) {
            return $SerialMatches
        }
    }

    if ([string]::IsNullOrWhiteSpace($DeviceName)) {
        return @()
    }

    return @($NameIndex.Find($DeviceName))
}
