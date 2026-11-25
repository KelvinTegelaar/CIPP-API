function Get-CIPPRoleAssignableGroupId {
    <#
    .SYNOPSIS
        Returns which of the given groups grant admin roles to their members.
    .DESCRIPTION
        Used before adding a member on behalf of a caller without Identity.PrivilegedUser.ReadWrite.
        A group that cannot be read is returned too, so a failed lookup never lets an add through.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string[]]$GroupId,
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $Ids = @($GroupId | Where-Object { $_ } | Select-Object -Unique)
    if ($Ids.Count -eq 0) { return }

    $GroupRequests = @($Ids | ForEach-Object { @{ id = [string]$_; method = 'GET'; url = "groups/$([uri]::EscapeDataString($_))?`$select=id,isAssignableToRole" } })
    $GroupResponses = @(New-GraphBulkRequest -tenantid $TenantFilter -Requests $GroupRequests)
    $Readable = @{}
    foreach ($Response in $GroupResponses) {
        if ($Response.status -eq 200 -and $Response.body.isAssignableToRole -ne $true) { $Readable[[string]$Response.id] = $true }
    }
    foreach ($Id in $Ids) {
        if (-not $Readable[[string]$Id]) { [string]$Id }
    }
}
