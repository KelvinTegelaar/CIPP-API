function Set-CIPPDBCacheServiceHealthIssues {
    <#
    .SYNOPSIS
        Caches Microsoft 365 service health incidents and advisories for a tenant

    .PARAMETER TenantFilter
        The tenant to cache service health issues for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching service health issues' -sev Debug
        $Issues = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/issues' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ServiceHealthIssues' -Data @($Issues) -AddCount -ClearOnEmpty

        # CippServiceHealth stores each issue body once and per-tenant links, so AllTenants reads skip every tenant's copy
        $HealthTable = Get-CIPPTable -tablename 'CippServiceHealth'
        # Every tenant reports the same issues, so a body is rewritten only when Microsoft changed it
        $Known = @{}
        foreach ($Stored in Get-CIPPAzDataTableEntity @HealthTable -Filter "PartitionKey eq 'Issue'" -Property PartitionKey, RowKey, LastModified) { $Known[$Stored.RowKey] = [string]$Stored.LastModified }
        $Rows = [System.Collections.Generic.List[object]]::new()
        $Current = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($Issue in $Issues) {
            if (-not $Issue.id) { continue }
            $Id = [string]$Issue.id
            $Modified = [string]$Issue.lastModifiedDateTime
            [void]$Current.Add("$TenantFilter|$Id")
            if ($Known[$Id] -ne $Modified) {
                $Body = [CIPP.CippJson]::ToJson($Issue, 20) ?? (ConvertTo-Json -InputObject $Issue -Depth 20 -Compress)
                $Rows.Add(@{ PartitionKey = 'Issue'; RowKey = $Id; isResolved = [bool]$Issue.isResolved; LastModified = $Modified; Data = $Body })
            }
            $Details = [CIPP.CippJson]::ToJson(@($Issue.details), 10) ?? (ConvertTo-Json -InputObject @($Issue.details) -Depth 10 -Compress)
            $Rows.Add(@{ PartitionKey = 'Tenant'; RowKey = "$TenantFilter|$Id"; Tenant = $TenantFilter; IssueId = $Id; isResolved = [bool]$Issue.isResolved; Details = $Details })
        }
        $Rows.Add(@{ PartitionKey = 'Collected'; RowKey = $TenantFilter })
        Add-CIPPAzDataTableEntity @HealthTable -Entity $Rows.ToArray() -Force

        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
        $Stale = foreach ($Link in Get-CIPPAzDataTableEntity @HealthTable -Filter "PartitionKey eq 'Tenant' and RowKey ge '$SafeTenant|' and RowKey lt '$SafeTenant}'" -Property PartitionKey, RowKey) {
            if (-not $Current.Contains($Link.RowKey)) { $Link }
        }
        if ($Stale) { Remove-AzDataTableEntity @HealthTable -Entity @($Stale) -Force }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached service health issues successfully' -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache service health issues: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
