function Get-CIPPTenantAllowBlockListReport {
    <#
    .SYNOPSIS
        Generates a Tenant Allow/Block List report from the CIPP Reporting database

    .DESCRIPTION
        Retrieves cached Tenant Allow/Block List entries for a tenant, or for every tenant at once,
        from the reporting database. The cache is populated by Set-CIPPDBCacheExoTenantAllowBlockList.

    .PARAMETER TenantFilter
        The tenant to generate the report for, or 'AllTenants'

    .EXAMPLE
        Get-CIPPTenantAllowBlockListReport -TenantFilter 'contoso.onmicrosoft.com'
        Gets all allow/block list entries for the tenant from the report database
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $Type = 'ExoTenantAllowBlockList'
    $CountRowKey = '{0}-Count' -f $Type

    try {
        if ($TenantFilter -eq 'AllTenants') {
            # One table query covers every tenant, then drop rows for tenants we no longer manage.
            $Rows = @(Get-CIPPDbItem -TenantFilter 'allTenants' -Type $Type | Where-Object { $_.RowKey -ne $CountRowKey })
            $TenantList = Get-Tenants -IncludeErrors
            $KnownDomains = [System.Collections.Generic.HashSet[string]]::new(
                [string[]]@($TenantList.defaultDomainName),
                [System.StringComparer]::OrdinalIgnoreCase
            )
            $Rows = @($Rows | Where-Object { $KnownDomains.Contains([string]$_.PartitionKey) })
        } else {
            $Rows = @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type $Type | Where-Object { $_.RowKey -ne $CountRowKey })
            if (-not $Rows) {
                throw 'No Tenant Allow/Block List data found in reporting database. Sync the report data first.'
            }
        }

        $Entries = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Row in $Rows) {
            $Entry = $Row.Data | ConvertFrom-Json
            $Entry | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Row.PartitionKey -Force
            # Per row rather than per report: each tenant is cached on its own schedule.
            $Entry | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $Row.Timestamp -Force
            $Entries.Add($Entry)
        }

        return $Entries | Sort-Object -Property Tenant, ListType, Value

    } catch {
        Write-LogMessage -API 'TenantAllowBlockListReport' -tenant $TenantFilter -message "Failed to generate Tenant Allow/Block List report: $($_.Exception.Message)" -sev Error
        throw
    }
}
