function Get-CippAuditLogSearchResults {
    <#
    .SYNOPSIS
        Get the results of an audit log search
    .DESCRIPTION
        Get the results of an audit log search from the Graph API
    .PARAMETER TenantFilter
        The tenant to filter on.
    .PARAMETER QueryId
        The ID of the query to get the results for.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Alias('id')]
        [string]$QueryId
    )

    process {
        New-GraphGetRequest -uri ('https://graph.microsoft.com/beta/security/auditLog/queries/{0}/records?$top=999' -f $QueryId) -AsApp $true -tenantid $TenantFilter -ErrorAction Stop
    }
}
