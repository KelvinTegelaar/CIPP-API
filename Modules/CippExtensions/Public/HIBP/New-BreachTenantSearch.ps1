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
        if ($null -eq $domain) {
            Write-Host "No breaches found for domain $($domain.clientDomain)"
            continue
        }
        $SumOfBreaches = ($LatestBreach | Measure-Object -Sum -Property found).sum
        if ($ExistingBreaches.sum -eq $SumOfBreaches -and $Force.IsPresent -eq $false) {
            Write-Host "No new breaches found for tenant $TenantFilter"
            continue
        }

        @{
            RowKey       = $domain.clientDomain
            PartitionKey = $TenantFilter
            breaches     = "$($LatestBreach | ConvertTo-Json -Depth 10 -Compress)"
            sum          = $SumOfBreaches
        }
    }

    #Add user breaches to table
    if ($usersResults) {
        try {
            $null = Add-CIPPAzDataTableEntity @Table -Entity $usersResults -Force
            return $LatestBreach
        } catch {
            Write-Error "Failed to add breaches to table: $($_.Exception.Message)"
            return $null
        }
    }
}
