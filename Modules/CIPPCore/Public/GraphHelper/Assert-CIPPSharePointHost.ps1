function Assert-CIPPSharePointHost {
    <#
    .SYNOPSIS
    Refuse to send a SharePoint token to a host that is not SharePoint
    .DESCRIPTION
    Does nothing unless -Scope is a SharePoint scope. Otherwise throws unless -Uri is an https
    URL on the same SharePoint domain. Any tenant or geo host passes: SharePoint itself rejects
    a token presented to the wrong tenant.
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [string]$Uri,
        [string]$Scope
    )

    if ($Scope -notmatch '^https://[^./]+\.(?<Domain>sharepoint(?:-[a-z]+)?\.[a-z.]+)(?:/|$)') { return }
    $Domain = $Matches.Domain

    $Parsed = $null
    if (-not [uri]::TryCreate($Uri, [System.UriKind]::Absolute, [ref]$Parsed) -or
        $Parsed.Scheme -ne 'https' -or $Parsed.UserInfo -or
        $Parsed.Host -notmatch "^[^.]+\.$([regex]::Escape($Domain))$") {
        throw "URL '$Uri' is not a SharePoint URL (expected https://<name>.$Domain)."
    }
}
