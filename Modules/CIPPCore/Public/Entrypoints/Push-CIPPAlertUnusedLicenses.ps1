function Push-CIPPAlertUnusedLicenses {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $QueueItem,
        $TriggerMetadata
    )


            try {
                $LicenseTable = Get-CIPPTable -TableName ExcludedLicenses
                $ExcludedSkuList = Get-CIPPAzDataTableEntity @LicenseTable
                New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $QueueItem.tenant | ForEach-Object {
                    $skuid = $_
                    foreach ($sku in $skuid) {
                        if ($sku.skuId -in $ExcludedSkuList.GUID) { continue }
                        $PrettyName = ($ConvertTable | Where-Object { $_.GUID -eq $sku.skuid }).'Product_Display_Name' | Select-Object -Last 1
                        if (!$PrettyName) { $PrettyName = $sku.skuPartNumber }
                        if ($sku.prepaidUnits.enabled - $sku.consumedUnits -gt 0) {
                            Write-AlertMessage -tenant $($QueueItem.tenant) -message "$PrettyName has unused licenses. Using $($_.consumedUnits) of $($_.prepaidUnits.enabled)."
                        }
                    }
                }
            } catch {
                Write-AlertMessage -tenant $($QueueItem.tenant) -message "Error occurred: $(Get-NormalizedError -message $_.Exception.message)"
            }
        }
