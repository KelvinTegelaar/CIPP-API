function Convert-SKUname {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param(
        $SkuName,
        $SkuID,
        $ConvertTable
    )
    if (!$ConvertTable) {
        $ModuleBase = Get-Module -Name CIPPCore | Select-Object -ExpandProperty ModuleBase
        $ConvertTable = Import-Csv (Join-Path $ModuleBase 'lib\data\ConversionTable.csv')
    }
    if ($SkuName) { $ReturnedName = ($ConvertTable | Where-Object { $_.String_Id -eq $SkuName } | Select-Object -Last 1).'Product_Display_Name' }
    if ($SkuID) { $ReturnedName = ($ConvertTable | Where-Object { $_.guid -eq $SkuID } | Select-Object -Last 1).'Product_Display_Name' }
    if ($ReturnedName) { return $ReturnedName } else { return $SkuName, $SkuID }
}
