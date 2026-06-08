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
        $AlertData = Get-CIPPLicenseOverview -TenantFilter $TenantFilter -AlertMode | ForEach-Object {
            if ([int]$_.CountAvailable -gt 0) {
                [PSCustomObject]@{
                    Message       = "$($_.License) has unused licenses. Using $($_.CountUsed) of $($_.TotalLicenses)."
                    LicenseName   = $_.License
                    SkuId         = $_.skuId
                    SkuPartNumber = $_.skuPartNumber
                    ConsumedUnits = $_.CountUsed
                    EnabledUnits  = $_.TotalLicenses
                    Tenant        = $TenantFilter
                }
            }
        }

        if ($AlertData) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Unused Licenses Alert Error occurred: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
