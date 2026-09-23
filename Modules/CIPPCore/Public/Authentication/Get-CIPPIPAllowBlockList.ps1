function Get-CIPPIPAllowBlockList {
    <#
    .SYNOPSIS
        Reads CIPP's IP allow/block list for a tenant.
    .DESCRIPTION
        The trustedIps table (managed from the Geo IP page) holds single addresses or CIDR ranges per
        tenant (PartitionKey = default domain) or for every tenant (PartitionKey = AllTenants), each
        Trusted or Blocked (NotTrusted rows are neutral and skipped). A CIDR range cannot be a table key,
        so its RowKey carries '_' for '/' and the range itself is in the Range property; rows from before
        ranges existed are a bare address in RowKey. Returns one entry per active row:
        { Range, State (Trusted|Blocked), Scope (Tenant|AllTenants), Prefix, Note }.
        Match an address against the result with Resolve-CIPPIPAllowBlockList.
    .PARAMETER TenantFilter
        The tenant's default domain name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$TenantFilter)

    $Table = Get-CIPPTable -TableName 'trustedIps'
    $SafeTenant = $TenantFilter -replace "'", "''"
    $Rows = Get-CIPPAzDataTableEntity @Table -Filter "(PartitionKey eq '$SafeTenant' or PartitionKey eq 'AllTenants') and (state eq 'Trusted' or state eq 'Blocked')"
    @(foreach ($Row in @($Rows | Where-Object { $_ })) {
            $Raw = if ($Row.Range) { [string]$Row.Range } else { ([string]$Row.RowKey) -replace '_', '/' }
            $Range = try { ConvertTo-CIPPIPRange -Value $Raw } catch { $null }
            if (-not $Range) { continue }
            $Prefix = if ($Range -match '/(\d+)$') { [int]$Matches[1] } elseif ($Range -match ':') { 128 } else { 32 }
            [pscustomobject]@{
                Range  = $Range
                State  = [string]$Row.state
                Scope  = if ($Row.PartitionKey -eq 'AllTenants') { 'AllTenants' } else { 'Tenant' }
                Prefix = $Prefix
                Note   = [string]$Row.Note
            }
        })
}
