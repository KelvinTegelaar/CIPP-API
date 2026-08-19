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
        # Project NONE of the split-entity markers (OriginalEntityId, PartIndex, PartCount,
        # SplitOverProps, chunk properties): excluding them all makes Get-AzDataTableLargeEntity
        # skip reassembly and return raw physical rows, part rows named '{RowKey}-part<n>'.
        # Projecting a SUBSET (e.g. OriginalEntityId alone) is poison - the module then
        # recognizes a split entity, fails to reassemble it from the truncated rows, and drops
        # it, silently losing exactly the tenants whose cached blob was split across rows.
        # Handing the raw part rows to Remove-CIPPAzDataTableEntity is safe: its own part-row
        # lookup skips rows already in the delete batch.
        $Existing = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
        if ($Existing) {
            $null = Remove-CIPPAzDataTableEntity -Force @Table -Entity $Existing
        }
        $GraphRequestParams = @{
            TenantFilter                = $Item.TenantFilter
            Endpoint                    = $Item.Endpoint
            Parameters                  = $Parameters
            NoPagination                = $Item.NoPagination
            ReverseTenantLookupProperty = $Item.ReverseTenantLookupProperty
            ReverseTenantLookup         = $Item.ReverseTenantLookup
            AsApp                       = $Item.AsApp ?? $false
            Caller                      = 'Push-ListGraphRequestQueue'
            SkipCache                   = $true
        }

        $RawGraphRequest = try {
            $Results = Get-GraphRequestList @GraphRequestParams
            if ($Results[-1].PSObject.Properties.Name -contains 'nextLink') {
                $Results | Select-Object -First ($Results.Count - 1)
            } else {
                $Results
            }
        } catch {
            $CippException = Get-CippException -Exception $_.Exception
            [PSCustomObject]@{
                Tenant        = $Item.TenantFilter
                CippStatus    = "Could not connect to tenant. $($CippException.NormalizedError)"
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

        if ($env:CIPPNG -eq 'true') {
            try {
                [Craft.Services.CacheBridge]::InvalidateByScope('AllTenants')
            } catch {
                Write-Information "CacheBridge invalidation skipped: $($_.Exception.Message)"
            }
        }

        return $true
    } catch {
        Write-Warning "Queue Error: $($_.Exception.Message)"
        #Write-Information ($GraphResults | ConvertTo-Json -Depth 10 -Compress)
        throw $_
    }
}
