function Find-HuduDeviceMatch {
    <#
        .SYNOPSIS
        Finds Hudu assets that correspond to an Intune managed device.

        .DESCRIPTION
        Uses a usable serial number first and falls back to the device name. Blank
        and excluded serial numbers never participate in serial matching.
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
        [string[]]$ExcludeSerials = @()
    )

    $SerialNumber = [string]$Device.serialNumber
    $DeviceName = [string]$Device.deviceName
    $SerialIsUsable = -not [string]::IsNullOrWhiteSpace($SerialNumber) -and $SerialNumber -notin $ExcludeSerials

    if ($SerialIsUsable) {
        $SerialMatches = @(
            $HuduDevices | Where-Object {
                $_.primary_serial -eq $SerialNumber -or
                ($_.cards | Where-Object {
                        $_.integrator_name -eq 'cw_manage' -and $_.data.serialNumber -eq $SerialNumber
                    })
            }
        )
        if ($SerialMatches.Count -gt 0) {
            return $SerialMatches
        }
    }

    if ([string]::IsNullOrWhiteSpace($DeviceName)) {
        return @()
    }

    return @(
        $HuduDevices | Where-Object {
            $_.name -eq $DeviceName -or
            ($_.cards | Where-Object {
                    $_.integrator_name -eq 'cw_manage' -and $_.data.name -contains $DeviceName
                })
        }
    )
}
