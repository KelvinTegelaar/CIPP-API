function Push-ListGraphRequestQueue {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    param($Item)

    Write-Information "PowerShell durable function processed work item: $($Item.Endpoint) - $($Item.TenantFilter)"

    try {
        $ParamCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)

        $Parameters = $Item.Parameters | ConvertTo-Json -Depth 5 | ConvertFrom-Json -AsHashtable
        foreach ($Param in ($Parameters.GetEnumerator() | Sort-Object -CaseSensitive -Property Key)) {
            $ParamCollection.Add($Param.Key, $Param.Value)
        }

        $PartitionKey = $Item.PartitionKey

        $TableName = ('cache{0}' -f ($Item.Endpoint -replace '[^A-Za-z0-9]'))[0..62] -join ''
        Write-Information "Queue Table: $TableName"
        $Table = Get-CIPPTable -TableName $TableName

        $Filter = "PartitionKey eq '{0}' and Tenant eq '{1}'" -f $PartitionKey, $Item.TenantFilter
        Write-Information "Filter: $Filter"
        $Existing = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
        if ($Existing) {
            $null = Remove-AzDataTableEntity @Table -Entity $Existing
        }
        $GraphRequestParams = @{
            TenantFilter                = $Item.TenantFilter
            Endpoint                    = $Item.Endpoint
            Parameters                  = $Parameters
            NoPagination                = $Item.NoPagination
            ReverseTenantLookupProperty = $Item.ReverseTenantLookupProperty
            ReverseTenantLookup         = $Item.ReverseTenantLookup
            SkipCache                   = $true
        }

        $RawGraphRequest = try {
            Get-GraphRequestList @GraphRequestParams
        } catch {
            [PSCustomObject]@{
                Tenant     = $Item.TenantFilter
                CippStatus = "Could not connect to tenant. $($_.Exception.message)"
            }
        }
        $GraphResults = foreach ($Request in $RawGraphRequest) {
            $Json = ConvertTo-Json -Depth 10 -Compress -InputObject $Request
            $RowKey = $Request.id ?? (New-Guid).Guid
            [PSCustomObject]@{
                Tenant       = [string]$Item.TenantFilter
                QueueId      = [string]$Item.QueueId
                QueueType    = [string]$Item.QueueType
                RowKey       = [string]$RowKey
                PartitionKey = [string]$PartitionKey
                Data         = [string]$Json
            }
        }
        Add-CIPPAzDataTableEntity @Table -Entity $GraphResults -Force | Out-Null
    } catch {
        Write-Information "Queue Error: $($_.Exception.Message)"
        throw $_
    }
}
