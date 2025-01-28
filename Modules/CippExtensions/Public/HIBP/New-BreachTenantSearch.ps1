function New-BreachTenantSearch {
    [CmdletBinding()]
    param (
        [Parameter()]$TenantFilter,
        [Parameter()][switch]$Force
    )

    $Table = Get-CIPPTable -TableName UserBreaches
    $LatestBreach = Get-BreachInfo -TenantFilter $TenantFilter

    $usersResults = foreach ($domain in $LatestBreach) {
        $ExistingBreaches = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$TenantFilter'"
        if ($null -eq $domain.result) {
            Write-Host "No breaches found for domain $($domain.domain)"
            continue
        }
        $SumOfBreaches = ($LatestBreach | Measure-Object -Sum -Property found).sum
        if ($ExistingBreaches.sum -eq $SumOfBreaches -and $Force.IsPresent -eq $false) {
            Write-Host "No new breaches found for tenant $TenantFilter"
            continue
        }

        @{
            RowKey       = $domain.domain
            PartitionKey = $TenantFilter
            breaches     = "$($LatestBreach.Result | ConvertTo-Json -Depth 10 -Compress)"
            sum          = $SumOfBreaches
        }
    }

    #Add user breaches to table
    if ($usersResults) {
        $entity = Add-CIPPAzDataTableEntity @Table -Entity $usersResults -Force
        return $LatestBreach.Result
    }
}
