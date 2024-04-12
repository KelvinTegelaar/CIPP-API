using namespace System.Net

Function Invoke-ListGenericAllTenants {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TableURLName = ($QueueItem.tolower().split('?').Split('/') | Select-Object -First 1).toString()
    $QueueKey = (Invoke-ListCippQueue | Where-Object -Property Name -EQ $TableURLName | Select-Object -Last 1).RowKey
    Update-CippQueueEntry -RowKey $QueueKey -Status 'Started'
    $Table = Get-CIPPTable -TableName "cache$TableURLName"
    $fullUrl = "https://graph.microsoft.com/beta/$QueueItem"
    Get-CIPPAzDataTableEntity @Table | Remove-AzDataTableEntity @table

    $RawGraphRequest = Get-Tenants | ForEach-Object -Parallel {
        $domainName = $_.defaultDomainName
        Import-Module '.\Modules\AzBobbyTables'
        Import-Module '.\Modules\CIPPCore'
        try {
            Write-Host $using:fullUrl
            New-GraphGetRequest -uri $using:fullUrl -tenantid $_.defaultDomainName -ComplexFilter -ErrorAction Stop | Select-Object *, @{l = 'Tenant'; e = { $domainName } }, @{l = 'CippStatus'; e = { 'Good' } }
        } catch {
            [PSCustomObject]@{
                Tenant     = $domainName
                CippStatus = "Could not connect to tenant. $($_.Exception.message)"
            }
        }
    }

    Update-CippQueueEntry -RowKey $QueueKey -Status 'Processing'
    foreach ($Request in $RawGraphRequest) {
        $Json = ConvertTo-Json -Compress -InputObject $request
        $GraphRequest = [PSCustomObject]@{
            Tenant       = [string]$Request.tenant
            RowKey       = [string](New-Guid)
            PartitionKey = [string]$URL
            Data         = [string]$Json

        }
        Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
    }


    Update-CippQueueEntry -RowKey $QueueKey -Status 'Completed'

}
