function Push-ListGraphRequestQueue {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    param($Item)

    # Write out the queue message and metadata to the information log.
    Write-Host "PowerShell queue trigger function processed work item: $($Item.Endpoint) - $($Item.TenantFilter)"

    #$TenantQueueName = '{0} - {1}' -f $Item.QueueName, $Item.TenantFilter
    #Update-CippQueueEntry -RowKey $Item.QueueId -Status 'Processing' -Name $TenantQueueName

    $ParamCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
    foreach ($Param in ($Item.Parameters.GetEnumerator() | Sort-Object -CaseSensitive -Property Key)) {
        $ParamCollection.Add($Param.Key, $Param.Value)
    }

    $PartitionKey = $Item.PartitionKey

    $TableName = ('cache{0}' -f ($Item.Endpoint -replace '[^A-Za-z0-9]'))[0..62] -join ''
    Write-Host "Queue Table: $TableName"
    $Table = Get-CIPPTable -TableName $TableName

    $Filter = "PartitionKey eq '{0}' and Tenant eq '{1}'" -f $PartitionKey, $Item.TenantFilter
    Write-Host "Filter: $Filter"
    Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey | Remove-AzDataTableEntity @Table

    $GraphRequestParams = @{
        TenantFilter                = $Item.TenantFilter
        Endpoint                    = $Item.Endpoint
        Parameters                  = $Item.Parameters
        NoPagination                = $Item.NoPagination
        ReverseTenantLookupProperty = $Item.ReverseTenantLookupProperty
        ReverseTenantLookup         = $Item.ReverseTenantLookup
        SkipCache                   = $true
    }

    $RawGraphRequest = try {
        Get-GraphRequestList @GraphRequestParams
    } catch {
        [PSCustomObject]@{
            Tenant     = $Item.Tenant
            CippStatus = "Could not connect to tenant. $($_.Exception.message)"
        }
    }

    $GraphResults = foreach ($Request in $RawGraphRequest) {
        $Json = ConvertTo-Json -Depth 5 -Compress -InputObject $Request
        [PSCustomObject]@{
            TenantFilter = [string]$Item.TenantFilter
            QueueId      = [string]$Item.QueueId
            QueueType    = [string]$Item.QueueType
            RowKey       = [string](New-Guid)
            PartitionKey = [string]$PartitionKey
            Data         = [string]$Json
        }
    }
    try {
        Add-CIPPAzDataTableEntity @Table -Entity $GraphResults -Force | Out-Null
    } catch {
        Write-Host "Queue Error: $($_.Exception.Message)"
        throw $_
    }
}