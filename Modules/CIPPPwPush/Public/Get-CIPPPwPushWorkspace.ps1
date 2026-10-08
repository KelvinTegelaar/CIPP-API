function Get-CIPPPwPushWorkspace {
    <#
    .SYNOPSIS
        Lists the Password Pusher workspaces (accounts) the token belongs to.
    .DESCRIPTION
        Calls /api/v2/workspaces (v2) or /api/v1/accounts (v1) and returns objects with a string id
        and a name. Needs a token; only hosted and Pro servers have workspaces.
    .PARAMETER Connection
        Object with BaseUrl, Headers and ApiVersion, built per call by the caller.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Connection
    )

    $Path = if ($Connection.ApiVersion -eq 'v2') { 'api/v2/workspaces' } else { 'api/v1/accounts' }
    $Response = Invoke-CIPPPwPushRequest -Uri "$($Connection.BaseUrl)/$Path" -Headers $Connection.Headers

    # Documented as a bare array; accept a wrapped list as well
    $Items = @($Response)
    if ($Items.Count -eq 1 -and $null -eq $Items[0].id) {
        $Items = @($Items[0].workspaces ?? $Items[0].accounts)
    }
    foreach ($Item in $Items) {
        if ($null -eq $Item -or [string]::IsNullOrEmpty("$($Item.id)")) { continue }
        [pscustomobject]@{ id = [string]$Item.id; name = [string]$Item.name }
    }
}
