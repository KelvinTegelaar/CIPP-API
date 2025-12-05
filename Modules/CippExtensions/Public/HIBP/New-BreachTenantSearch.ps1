function New-BreachTenantSearch {
    [CmdletBinding()]
    param (
        [Parameter()]$TenantFilter,
        [Parameter()][switch]$Force
    )

    $Table = Get-CIPPTable -TableName UserBreaches
    $LatestBreach = Get-BreachInfo -TenantFilter $TenantFilter | ForEach-Object {
        $_ | Where-Object { $_ -and $_.email }
    } | Group-Object -Property clientDomain

    $usersResults = foreach ($domain in $LatestBreach) {
        $ExistingBreaches = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($domain.name)'"
        if ($null -eq $domain.Group) {
            Write-Host "No breaches found for domain $($domain.name)"
            continue
        }
        $SumOfBreaches = $domain.Count
        if ($ExistingBreaches.sum -eq $SumOfBreaches) {
            if ($Force.IsPresent -eq $true) {
                Write-Host "Forcing update for tenant $TenantFilter"
            } else {
                Write-Host "No new breaches found for tenant $TenantFilter"
                continue
            }
        }

        @{
            RowKey       = $domain.name
            PartitionKey = $TenantFilter
            breaches     = "$($domain.Group | ConvertTo-Json -Depth 10 -Compress)"
            sum          = $SumOfBreaches
        }
    }

    #Add user breaches to table
    if ($usersResults) {
        try {
            $null = Add-CIPPAzDataTableEntity @Table -Entity $usersResults -Force
            return $LatestBreach.Group
        } catch {
            Write-Error "Failed to add breaches to table: $($_.Exception.Message)"
            return $null
        }
    }
}
