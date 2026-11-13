function Get-CIPPConversionTable {
    <#
    .SYNOPSIS
        Licence SKU and service plan lookups built from the shipped ConversionTable.csv
    .DESCRIPTION
        Parses the 6,000-row CSV once per worker (once per task on background workers) into read-only maps. Where a
        key repeats, the first row wins: the CSV lists a renamed product's current name before its retired one.
        SKU ids, part numbers and service plan keys are trimmed and the SKU and plan ids lower-cased.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    if ($script:CIPPConversionTable) { return $script:CIPPConversionTable }

    $Table = [pscustomobject]@{
        NameBySkuId       = @{}   # SKU id -> product display name
        NameByPartNumber  = @{}   # SKU part number (String_Id) -> product display name
        PartNumberBySkuId = @{}   # SKU id -> SKU part number
        PlanIdsBySkuId    = @{}   # SKU id -> service plan ids it includes
        PlanNameByPlanId  = @{}   # service plan id -> friendly name
        PlanNameByName    = @{}   # service plan name -> friendly name
    }
    foreach ($Row in [System.IO.File]::ReadAllText((Join-Path $env:CIPPRootPath 'Config\ConversionTable.csv')) | ConvertFrom-Csv) {
        $SkuId = ([string]$Row.GUID).Trim().ToLowerInvariant()
        $PartNumber = ([string]$Row.String_Id).Trim()
        $PlanId = ([string]$Row.Service_Plan_Id).Trim().ToLowerInvariant()
        $PlanName = ([string]$Row.Service_Plan_Name).Trim()
        $Friendly = [string]$Row.Service_Plans_Included_Friendly_Names
        if ($SkuId) {
            if (-not $Table.NameBySkuId.ContainsKey($SkuId)) {
                $Table.NameBySkuId[$SkuId] = [string]$Row.Product_Display_Name
                $Table.PartNumberBySkuId[$SkuId] = $PartNumber
                $Table.PlanIdsBySkuId[$SkuId] = [System.Collections.Generic.List[string]]::new()
            }
            if ($PlanId) { $Table.PlanIdsBySkuId[$SkuId].Add($PlanId) }
        }
        if ($PartNumber -and -not $Table.NameByPartNumber.ContainsKey($PartNumber)) { $Table.NameByPartNumber[$PartNumber] = [string]$Row.Product_Display_Name }
        if ($Friendly) {
            if ($PlanId -and -not $Table.PlanNameByPlanId.ContainsKey($PlanId)) { $Table.PlanNameByPlanId[$PlanId] = $Friendly }
            if ($PlanName -and -not $Table.PlanNameByName.ContainsKey($PlanName)) { $Table.PlanNameByName[$PlanName] = $Friendly }
        }
    }
    $script:CIPPConversionTable = $Table
    $Table
}
