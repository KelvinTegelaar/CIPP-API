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
        $ConvertTable = [System.IO.File]::ReadAllText((Join-Path $env:CIPPRootPath 'Config\ConversionTable.csv')) | ConvertFrom-Csv
    }
    if ($SkuName) { $ReturnedName = ($ConvertTable | Where-Object { $_.String_Id -eq $SkuName } | Select-Object -Last 1).'Product_Display_Name' }
    if ($SkuID) { $ReturnedName = ($ConvertTable | Where-Object { $_.guid -eq $SkuID } | Select-Object -Last 1).'Product_Display_Name' }
    if ($ReturnedName) { return $ReturnedName } else { return $SkuName, $SkuID }
}
