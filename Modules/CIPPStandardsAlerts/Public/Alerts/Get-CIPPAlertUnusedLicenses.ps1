function Get-CIPPAlertUnusedLicenses {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        $LicenseTable = Get-CIPPTable -TableName ExcludedLicenses
        $ExcludedSkuList = Get-CIPPAzDataTableEntity @LicenseTable
        $AlertData = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $TenantFilter | ForEach-Object {
            $SkuId = $_
            foreach ($sku in $SkuId) {
                if ($sku.skuId -in $ExcludedSkuList.GUID) { continue }
                $PrettyName = Convert-SKUname -SkuID $sku.skuId
                if (!$PrettyName) { $PrettyName = $sku.skuPartNumber }
                if ($sku.prepaidUnits.enabled - $sku.consumedUnits -gt 0) {
                    [PSCustomObject]@{
                        Message       = "$PrettyName has unused licenses. Using $($sku.consumedUnits) of $($sku.prepaidUnits.enabled)."
                        LicenseName   = $PrettyName
                        SkuId         = $sku.skuId
                        SkuPartNumber = $sku.skuPartNumber
                        ConsumedUnits = $sku.consumedUnits
                        EnabledUnits  = $sku.prepaidUnits.enabled
                        Tenant        = $TenantFilter
                    }
                }
            }
        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Unused Licenses Alert Error occurred: $(Get-NormalizedError -message $_.Exception.message)"
    }
}
