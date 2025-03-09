function Get-CIPPAlertUnusedLicenses {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        $LicenseTable = Get-CIPPTable -TableName ExcludedLicenses
        $ExcludedSkuList = Get-CIPPAzDataTableEntity @LicenseTable
        $AlertData = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $TenantFilter | ForEach-Object {
            $skuId = $_
            foreach ($sku in $skuId) {
                if ($sku.skuId -in $ExcludedSkuList.GUID) { continue }
                $PrettyName = ($ConvertTable | Where-Object { $_.GUID -eq $sku.skuId }).'Product_Display_Name' | Select-Object -Last 1
                if (!$PrettyName) { $PrettyName = $sku.skuPartNumber }
                if ($sku.prepaidUnits.enabled - $sku.consumedUnits -gt 0) {
                    "$PrettyName has unused licenses. Using $($_.consumedUnits) of $($_.prepaidUnits.enabled)."
                }
            }
        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Unused Licenses Alert Error occurred: $(Get-NormalizedError -message $_.Exception.message)"
    }
}
