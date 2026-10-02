function Get-HuduDeviceMatchKey {
    <#
        .SYNOPSIS
        Returns the serial and name values a Hudu asset can be matched on.

        .DESCRIPTION
        Serials are the primary serial and the serial of any ConnectWise Manage card; names are the asset name and
        the names of any ConnectWise Manage card. Find-HuduDeviceMatch indexes assets by these values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$HuduDevice
    )

    $ManageData = @($HuduDevice.cards | Where-Object { $_.integrator_name -eq 'cw_manage' }).data
    [PSCustomObject]@{
        Serial = @($HuduDevice.primary_serial; $ManageData.serialNumber)
        Name   = @($HuduDevice.name; $ManageData.name)
    }
}
