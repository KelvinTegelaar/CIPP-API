function Get-SyncroSubdomain {
    <#
    .SYNOPSIS
        Reduces the Syncro Subdomain setting to a bare subdomain.
    .DESCRIPTION
        Admins paste what their browser shows, which is anything from "contoso" to
        "https://contoso.syncromsp.com/tickets". Strip the scheme, the syncromsp.com host suffix
        and any path so the request builder can always put it in front of .syncromsp.com.
    .PARAMETER Subdomain
        The raw setting value.
    #>
    [CmdletBinding()]
    param (
        [string]$Subdomain
    )

    if ([string]::IsNullOrWhiteSpace($Subdomain)) { return '' }

    $Value = $Subdomain.Trim()
    $Value = $Value -replace '^(?i)https?://', ''
    # Everything from the first slash on is a path, never part of the subdomain.
    $Value = ($Value -split '/')[0]
    $Value = $Value -replace '(?i)\.syncromsp\.com$', ''
    return $Value.Trim().ToLowerInvariant()
}
