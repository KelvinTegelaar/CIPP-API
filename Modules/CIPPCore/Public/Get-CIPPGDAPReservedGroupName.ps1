function Get-CIPPGDAPReservedGroupName {
    <#
    .SYNOPSIS
        Partner tenant groups that must never be mapped to a GDAP role
    .DESCRIPTION
        Microsoft-managed partner groups whose membership already carries partner permissions; every path
        that maps a group to a role refuses these by display name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()
    @('All Users', 'AdminAgents', 'HelpdeskAgents', 'SalesAgents')
}
