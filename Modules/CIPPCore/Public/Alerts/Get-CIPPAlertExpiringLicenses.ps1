function Get-CIPPAlertExpiringLicenses {
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
        $AlertData = Get-CIPPLicenseOverview -TenantFilter $TenantFilter | ForEach-Object {
            $TermData = $_.TermInfo | ConvertFrom-Json
            foreach ($Term in $TermData) {
                if ($Term.DaysUntilRenew -lt 30 -and $Term.DaysUntilRenew -gt 0) {
                    Write-Host "$($_.License) will expire in $($Term.DaysUntilRenew) days. The estimated term is $($Term.Term)"
                    [PSCustomObject]@{
                        Message        = "$($_.License) will expire in $($Term.DaysUntilRenew) days. The estimated term is $($Term.Term)"
                        License        = $_.License
                        SkuId          = $_.skuId
                        DaysUntilRenew = $Term.DaysUntilRenew
                        Term           = $Term.Term
                        Status         = $Term.Status
                        TotalLicenses  = $Term.TotalLicenses
                        CountUsed      = $_.CountUsed
                        NextLifecycle  = $Term.NextLifecycle
                        Tenant         = $_.Tenant
                    }
                }
            }
        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

    } catch {
    }
}

