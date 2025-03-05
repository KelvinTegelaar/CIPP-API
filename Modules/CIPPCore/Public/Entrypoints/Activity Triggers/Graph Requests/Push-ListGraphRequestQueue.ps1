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

        $Filter = "PartitionKey eq '{0}' and (RowKey eq '{1}' or OriginalEntityId eq '{1}')" -f $PartitionKey, $Item.TenantFilter
        Write-Information "Filter: $Filter"
        $Existing = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey, OriginalEntityId
        if ($Existing) {
            $null = Remove-AzDataTableEntity -Force @Table -Entity $Existing
        }
        $GraphRequestParams = @{
            TenantFilter                = $Item.TenantFilter
            Endpoint                    = $Item.Endpoint
            Parameters                  = $Parameters
            NoPagination                = $Item.NoPagination
            ReverseTenantLookupProperty = $Item.ReverseTenantLookupProperty
            ReverseTenantLookup         = $Item.ReverseTenantLookup
            AsApp                       = $Item.AsApp ?? $false
            SkipCache                   = $true
        }

        $RawGraphRequest = try {
            $Results = Get-GraphRequestList @GraphRequestParams
            $Results | Select-Object -First ($Results.Count - 1)
        } catch {
            $CippException = Get-CippException -Exception $_.Exception
            [PSCustomObject]@{
                Tenant     = $Item.TenantFilter
                CippStatus = "Could not connect to tenant. $($CippException.NormalizedMessage)"
                CippException = [string]($CippException | ConvertTo-Json -Depth 10 -Compress)
            }
        }
        $Json = ConvertTo-Json -Depth 10 -Compress -InputObject $RawGraphRequest
        $GraphResults = [PSCustomObject]@{
            PartitionKey = [string]$PartitionKey
            RowKey       = [string]$Item.TenantFilter
            QueueId      = [string]$Item.QueueId
            QueueType    = [string]$Item.QueueType
            Data         = [string]$Json
        }
        Add-CIPPAzDataTableEntity @Table -Entity $GraphResults -Force | Out-Null
        return $true
    } catch {
        Write-Warning "Queue Error: $($_.Exception.Message)"
        #Write-Information ($GraphResults | ConvertTo-Json -Depth 10 -Compress)
        throw $_
    }
}
