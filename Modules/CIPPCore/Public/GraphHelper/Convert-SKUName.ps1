function Convert-SKUname {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param(
        $skuname,
        $skuID,
        $ConvertTable
    )
    if (!$ConvertTable) {
        Set-Location (Get-Item $PSScriptRoot).Parent.FullName
        $ConvertTable = Import-Csv Conversiontable.csv
    }
    if ($skuname) { $ReturnedName = ($ConvertTable | Where-Object { $_.String_Id -eq $skuname } | Select-Object -Last 1).'Product_Display_Name' }
    if ($skuID) { $ReturnedName = ($ConvertTable | Where-Object { $_.guid -eq $skuid } | Select-Object -Last 1).'Product_Display_Name' }
    if ($ReturnedName) { return $ReturnedName } else { return $skuname, $skuID }
}
