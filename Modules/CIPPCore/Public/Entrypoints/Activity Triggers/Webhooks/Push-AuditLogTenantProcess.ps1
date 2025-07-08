function Push-AuditLogTenantProcess {
    Param($Item)
    $TenantFilter = $Item.TenantFilter
    $RowIds = $Item.RowIds

    try {
        Write-Information "Audit Logs: Processing $($TenantFilter) with $($RowIds.Count) row IDs. We're processing id $($RowIds[0]) to $($RowIds[-1])"

        # Get the CacheWebhooks table
        $CacheWebhooksTable = Get-CippTable -TableName 'CacheWebhooks'
        # we do it this way because the rows can grow extremely large, if we get them all it might just hang for minutes at a time.
        $Rows = foreach ($RowId in $RowIds) {
            $CacheEntity = Get-CIPPAzDataTableEntity @CacheWebhooksTable -Filter "PartitionKey eq '$TenantFilter' and RowKey eq '$RowId'"
            if ($CacheEntity) {
                $AuditData = $CacheEntity.JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
                $AuditData
            }
        }

        if ($Rows.Count -gt 0) {
            Write-Information "Retrieved $($Rows.Count) rows from cache for processing"
            Test-CIPPAuditLogRules -TenantFilter $TenantFilter -Rows $Rows
            exit 0
        } else {
            Write-Information 'No rows found in cache for the provided row IDs'
            exit 0
        }
    } catch {
        Write-Information ('Push-AuditLogTenant: Error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
    }
}
