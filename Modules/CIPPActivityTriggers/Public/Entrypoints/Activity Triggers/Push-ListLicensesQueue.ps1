function Push-ListLicensesQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    # Write out the queue message and metadata to the information log.
    Write-Host "PowerShell queue trigger function processed work item: $($Item.defaultDomainName)"

    $domainName = $Item.defaultDomainName
    try {
        Write-Host "Processing $domainName"
        $Licenses = Get-CIPPLicenseOverview -TenantFilter $domainName
    } catch {
        $Licenses = [pscustomobject]@{
            Tenant         = [string]$domainName
            License        = "Could not connect to client: $($_.Exception.Message)"
            'PartitionKey' = 'License'
            'RowKey'       = "$($domainName)"
        }
    } finally {
        $Table = Get-CIPPTable -TableName cachelicenses
        $JSON = ConvertTo-Json -Depth 10 -Compress -InputObject @($Licenses)
        $Overview = [pscustomobject]@{
            License        = [string]$JSON
            'PartitionKey' = 'License'
            'RowKey'       = "$($domainName)"
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Overview -Force | Out-Null
    }
}
