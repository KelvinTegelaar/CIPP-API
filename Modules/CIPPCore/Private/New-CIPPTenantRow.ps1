function New-CIPPTenantRow {
    <#
    .FUNCTIONALITY
    Internal
    .SYNOPSIS
    Builds a Tenants table row object for Get-Tenants.
    .DESCRIPTION
    Shared row constructor for Get-Tenants.
    .PARAMETER Item
    The pending-tenant object built from the grouped GDAP relationships (customerId,
    partnerTenantId, assignmentMode, knownPartners, displayName, relationshipEnd,
    relationshipCount, hasAutoExtend).
    .PARAMETER DefaultDomainName
    Resolved default domain.
    .PARAMETER InitialDomainName
    Resolved (or provisional) initial domain.
    .PARAMETER RequiresRefresh
    Whether the row still needs the authoritative background domain lookup.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Item,
        [Parameter(Mandatory = $true)][string]$DefaultDomainName,
        [string]$InitialDomainName,
        [bool]$RequiresRefresh
    )

    [PSCustomObject]@{
        PartitionKey             = 'Tenants'
        RowKey                   = $Item.customerId
        customerId               = $Item.customerId
        displayName              = $Item.displayName
        relationshipEnd          = $Item.relationshipEnd
        relationshipCount        = $Item.relationshipCount
        defaultDomainName        = $DefaultDomainName
        initialDomainName        = if ($InitialDomainName) { $InitialDomainName } else { $DefaultDomainName }
        hasAutoExtend            = $Item.hasAutoExtend
        delegatedPrivilegeStatus = 'granularDelegatedAdminPrivileges'
        partnerTenantId          = $Item.partnerTenantId
        partnerAssignmentMode    = $Item.assignmentMode
        knownPartners            = $Item.knownPartners
        domains                  = ''
        Excluded                 = $false
        ExcludeUser              = ''
        ExcludeDate              = ''
        GraphErrorCount          = 0
        LastGraphError           = ''
        RequiresRefresh          = $RequiresRefresh
        LastRefresh              = (Get-Date).ToUniversalTime()
    }
}
