function Get-CIPPAlertOverusedLicenses {
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
            $skuid = $_
            foreach ($sku in $skuid) {
                if ($sku.skuId -in $ExcludedSkuList.GUID) { continue }
                $PrettyName = ($ConvertTable | Where-Object { $_.GUID -eq $sku.skuid }).'Product_Display_Name' | Select-Object -Last 1
                if (!$PrettyName) { $PrettyName = $sku.skuPartNumber }
                if ($sku.prepaidUnits.enabled - $sku.consumedUnits -lt 0) {
                    "$PrettyName has Overused licenses. Using $($_.consumedUnits) of $($_.prepaidUnits.enabled)."
                }
            }

        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Overused Licenses Alert Error occurred: $(Get-NormalizedError -message $_.Exception.message)"
    }
}
