function Clear-CIPPDbCache {
    <#
    .SYNOPSIS
        Remove every CippReportingDB row for a cache type and reset the Count row to 0.

    .DESCRIPTION
        SuperAdmin empty path.

        Rows are read and deleted physically rather than as reassembled large entities, so any
        part rows a split entity left behind go with it.

        The delete is re-read afterwards and a row that survived is an error. Table deletes
        report success for a row the service says does not exist - the SDK returns 404 as a
        response rather than throwing, and AzBobbyTables' large-entity remove swallows it in
        its per-row fallback - so an empty that only trusted the delete call could report
        clearing rows it never touched.

    .PARAMETER TenantFilter
        Tenant domain, GUID, or AllTenants.

    .PARAMETER Type
        Cache collection name (e.g. Users, Groups, Mailboxes).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$Type
    )

    try {
        $Table = Get-CippTable -tablename 'CippReportingDB'
        $IsAllTenants = $TenantFilter -eq 'AllTenants' -or $TenantFilter -eq 'allTenants'
        $TypeName = [string]$Type
        $CountRowKey = "$TypeName-Count"

        if ($IsAllTenants) {
            $Filter = "RowKey ge '$TypeName-' and RowKey lt '${TypeName}0'"
            $ResultTenant = 'AllTenants'
            $DbTenant = $null
        } else {
            $Tenant = Get-Tenants -TenantFilter $TenantFilter
            if (-not $Tenant) {
                throw "Tenant '$TenantFilter' not found"
            }
            $DbTenant = [string]$Tenant.defaultDomainName
            if ([string]::IsNullOrWhiteSpace($DbTenant)) {
                throw "Tenant '$TenantFilter' has no defaultDomainName"
            }
            $ResultTenant = $DbTenant
            $Filter = "PartitionKey eq '$DbTenant' and RowKey ge '$TypeName-' and RowKey lt '${TypeName}0'"
        }

        $Rows = @(Get-AzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey -ErrorAction Stop)

        $TouchedPartitions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Entities = [System.Collections.Generic.List[object]]::new()
        foreach ($Row in $Rows) {
            $Pk = [string]$Row.PartitionKey
            $Rk = [string]$Row.RowKey
            if ([string]::IsNullOrWhiteSpace($Pk) -or [string]::IsNullOrWhiteSpace($Rk)) { continue }
            [void]$TouchedPartitions.Add($Pk)
            if ($Rk -eq $CountRowKey) { continue }
            $Entities.Add([pscustomobject]@{ PartitionKey = $Pk; RowKey = $Rk })
        }

        $RemovedCount = 0
        if ($Entities.Count -gt 0) {
            # One call: the module splits the entities into transactions per partition key and
            # per the service's 100-operation limit, so an AllTenants clear needs no grouping here.
            Remove-AzDataTableEntity @Table -Entity $Entities.ToArray() -Force -ErrorAction Stop
            $RemovedCount = $Entities.Count
        }

        if (-not $IsAllTenants) {
            [void]$TouchedPartitions.Add($DbTenant)
        }

        foreach ($Partition in $TouchedPartitions) {
            $null = Add-CIPPAzDataTableEntity @Table -Entity @{
                PartitionKey = $Partition
                RowKey       = $CountRowKey
                DataCount    = 0
                Type         = $TypeName
            } -Force
        }

        $StillThere = @(Get-AzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey -ErrorAction Stop |
                Where-Object { [string]$_.RowKey -ne $CountRowKey })
        if ($StillThere.Count -gt 0) {
            $Sample = ($StillThere | Select-Object -First 3 | ForEach-Object { "$($_.PartitionKey)/$($_.RowKey)" }) -join ', '
            throw "Deleted $RemovedCount $TypeName row(s) for $TenantFilter but $($StillThere.Count) still exist (e.g. $Sample)"
        }

        Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Cleared $RemovedCount $TypeName cache row(s) for $TenantFilter" -sev Warning
        return [PSCustomObject]@{
            RemovedCount = $RemovedCount
            Tenant       = $ResultTenant
            Type         = $TypeName
        }
    } catch {
        Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Failed to clear $Type cache: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
