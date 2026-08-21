function Push-AuditLogTenantProcess {
    param($Item)
    $TenantFilter = $Item.TenantFilter
    $RowIds = $Item.RowIds

    try {
        Write-Information "Audit Logs: Processing $($TenantFilter) with $($RowIds.Count) row IDs. We're processing id $($RowIds[0]) to $($RowIds[-1])"

        # Get the CacheWebhooks table
        $CacheWebhooksTable = Get-CippTable -TableName 'CacheWebhooks'
        # we do it this way because the rows can grow extremely large, if we get them all it might just hang for minutes at a time.
        $Poison = [System.Collections.Generic.List[object]]::new()
        $Rows = foreach ($RowId in $RowIds) {
            $CacheEntity = Get-CIPPAzDataTableEntity @CacheWebhooksTable -Filter "PartitionKey eq '$TenantFilter' and RowKey eq '$RowId'"
            if ($CacheEntity) {
                # try/catch, not -ErrorAction: ConvertFrom-Json parse failures are terminating,
                # so without the catch one garbled row aborts the whole batch via the outer catch.
                try {
                    $AuditData = $CacheEntity.JSON | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    $AuditData = $null
                }
                if ($null -eq $AuditData) {
                    # A row whose JSON can never parse can never be drained; left in place it
                    # re-enters every claim cycle forever. Delete it.
                    Write-Information "Audit Logs: removing unparseable cache row $($CacheEntity.RowKey) ($TenantFilter)"
                    $Poison.Add([PSCustomObject]@{ PartitionKey = [string]$CacheEntity.PartitionKey; RowKey = [string]$CacheEntity.RowKey })
                    continue
                }
                $AuditData
            }
        }
        if ($Poison.Count -gt 0) {
            try {
                $null = Remove-CIPPAzDataTableEntity -Force @CacheWebhooksTable -Entity $Poison.ToArray()
            } catch {
                Write-Information "Audit Logs: failed to remove $($Poison.Count) unparseable row(s) for ${TenantFilter}: $($_.Exception.Message)"
            }
        }

        if ($Rows.Count -gt 0) {
            Write-Information "Retrieved $($Rows.Count) rows from cache for processing"
            Test-CIPPAuditLogRules -TenantFilter $TenantFilter -Rows $Rows
            return $true
        } else {
            Write-Information 'No rows found in cache for the provided row IDs'
            return $false
        }
    } catch {
        Write-Information ('Push-AuditLogTenant: Error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
        return $false
    }
}
