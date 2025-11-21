function Get-CIPPAlertOverusedLicenses {
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
            $skuid = $_
            foreach ($sku in $skuid) {
                if ($sku.skuId -in $ExcludedSkuList.GUID) { continue }
                $PrettyName = Convert-SKUname -SkuID $sku.skuId
                if (!$PrettyName) { $PrettyName = $sku.skuPartNumber }
                if ($sku.prepaidUnits.enabled - $sku.consumedUnits -lt 0) {
                    [PSCustomObject]@{
                        Message       = "$PrettyName has Overused licenses. Using $($sku.consumedUnits) of $($sku.prepaidUnits.enabled)."
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
        if ($AlertData) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }

    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Overused Licenses Alert Error occurred: $(Get-NormalizedError -message $_.Exception.message)"
    }
}
