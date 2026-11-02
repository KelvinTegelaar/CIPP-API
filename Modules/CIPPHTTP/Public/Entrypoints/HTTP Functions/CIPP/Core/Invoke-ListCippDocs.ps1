function Invoke-ListCippDocs {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    .SYNOPSIS
        Search the CIPP documentation, or fetch one documentation page in full.
    .DESCRIPTION
        Searches the GitBook documentation shipped with this build and returns matching sections,
        each with an excerpt and links back to docs.cipp.app and to the file on GitHub. Pages under
        user-documentation also report the CIPP route they document, so a screen can be traced to
        its docs and back.

        Pass path on its own to list the pages under a documentation subtree or a CIPP route, or
        with full=true to return one page's entire text. This backs the SearchDocs and GetDoc MCP
        tools and is available to the UI and API clients on the same terms.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Headers = $Request.Headers

    # Keywords or a plain-language question, e.g. 'how do I set up GDAP'.
    $Query = $Request.Query.query ?? $Request.Body.query
    # A documentation subtree ('user-documentation/identity') or a CIPP route
    # ('/identity/administration/users').
    $Path = $Request.Query.path ?? $Request.Body.path
    # Return the whole page rather than matching sections. Requires path.
    $Full = [bool]($Request.Query.full ?? $Request.Body.full)
    # Maximum results to return (default 8, max 25).
    $Limit = ($Request.Query.limit ?? $Request.Body.limit) -as [int]

    try {
        if ($Full) {
            if (-not $Path) { throw 'path is required when full=true.' }
            $Result = Get-CippDoc -Path $Path
        } else {
            $Result = Find-CippDoc -Query ([string]$Query) -Path ([string]$Path) -Limit $Limit
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -API 'ListCippDocs' -message "Documentation search failed: $($_.Exception.Message)" -sev Error -headers $Headers
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Result = @{ error = $_.Exception.Message }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Result
        })
}
