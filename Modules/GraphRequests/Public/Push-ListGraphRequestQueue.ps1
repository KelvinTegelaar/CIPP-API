function Push-ListGraphRequestQueue {
    # Input bindings are passed in via param block.
    param($QueueItem, $TriggerMetadata)

    # Write out the queue message and metadata to the information log.
    Write-Host "PowerShell queue trigger function processed work item: $($QueueItem.Endpoint) - $($QueueItem.Tenant)"

    #Write-Host ($QueueItem | ConvertTo-Json -Depth 5)

    $TenantQueueName = '{0} - {1}' -f $QueueItem.QueueName, $QueueItem.Tenant
    Update-CippQueueEntry -RowKey $QueueItem.QueueId -Status 'Processing' -Name $TenantQueueName

    $ParamCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
    foreach ($Item in ($QueueItem.Parameters.GetEnumerator() | Sort-Object -CaseSensitive -Property Key)) {
        $ParamCollection.Add($Item.Key, $Item.Value)
    }

    $PartitionKey = $QueueItem.PartitionKey

    $TableName = ('cache{0}' -f ($QueueItem.Endpoint -replace '[^A-Za-z0-9]'))[0..63] -join ''
    Write-Host $TableName
    $Table = Get-CIPPTable -TableName $TableName

    $Filter = "PartitionKey eq '{0}' and Tenant eq '{1}'" -f $PartitionKey, $QueueItem.Tenant
    Write-Host $Filter
    Get-AzDataTableEntity @Table -Filter $Filter | Remove-AzDataTableEntity @Table

    $GraphRequestParams = @{
        Tenant                      = $QueueItem.Tenant
        Endpoint                    = $QueueItem.Endpoint
        Parameters                  = $QueueItem.Parameters
        NoPagination                = $QueueItem.NoPagination
        ReverseTenantLookupProperty = $QueueItem.ReverseTenantLookupProperty
        ReverseTenantLookup         = $QueueItem.ReverseTenantLookup
        SkipCache                   = $true
    }

    $RawGraphRequest = try {
        Get-GraphRequestList @GraphRequestParams
    } catch {
        [PSCustomObject]@{
            Tenant     = $QueueItem.Tenant
            CippStatus = "Could not connect to tenant. $($_.Exception.message)"
        }
    }

    $GraphResults = foreach ($Request in $RawGraphRequest) {
        $Json = ConvertTo-Json -Depth 5 -Compress -InputObject $Request
        [PSCustomObject]@{
            Tenant       = [string]$QueueItem.Tenant
            QueueId      = [string]$QueueItem.QueueId
            QueueType    = [string]$QueueItem.QueueType
            RowKey       = [string](New-Guid)
            PartitionKey = [string]$PartitionKey
            Data         = [string]$Json
        }
    }
    try {
        Add-AzDataTableEntity @Table -Entity $GraphResults -Force | Out-Null
        Update-CippQueueEntry -RowKey $QueueItem.QueueId -Status 'Completed'
    } catch {
        Write-Host "Queue Error: $($_.Exception.Message)"
        Update-CippQueueEntry -RowKey $QueueItem.QueueId -Status 'Failed'
    }
}