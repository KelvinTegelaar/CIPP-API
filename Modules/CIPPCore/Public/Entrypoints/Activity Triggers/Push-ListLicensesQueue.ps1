function Push-ListLicensesQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    # Write out the queue message and metadata to the information log.
    Write-Host "PowerShell queue trigger function processed work item: $($Item.defaultDomainName)"

    $domainName = $Item.defaultDomainName
    $GraphRequest = try {
        Write-Host "Processing $domainName"
        Get-CIPPLicenseOverview -TenantFilter $domainName
    } catch {
        [pscustomobject]@{
            Tenant         = [string]$domainName
            License        = "Could not connect to client: $($_.Exception.Message)"
            'PartitionKey' = 'License'
            'RowKey'       = "$($domainName)-$((New-Guid).Guid)"
        }
    }
    $Table = Get-CIPPTable -TableName cachelicenses
    Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
}