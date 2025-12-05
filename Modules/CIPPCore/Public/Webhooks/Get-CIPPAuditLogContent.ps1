function Get-CIPPAuditLogContent {
    <#
    .SYNOPSIS
        Get the content of an audit log.
    .PARAMETER ContentUri
        The URI of the content to get.
    .PARAMETER TenantFilter
        The tenant to filter on.
    .EXAMPLE
        Get-CIPPAuditLogContent -ContentUri 'https://manage.office.com/api/v1.0/contoso.com/activity/feed/subscriptions/content?contentType=Audit.General&PublisherIdentifier=00000000-0000-0000-0000-000000000000' -TenantFilter 'contoso.com'
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string[]]$ContentUri,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string]$TenantFilter
    )

    Process {
        foreach ($Uri in $ContentUri) {
            New-GraphPOSTRequest -type GET -uri $Uri -tenantid $TenantFilter -scope 'https://manage.office.com/.default'
        }
    }
}