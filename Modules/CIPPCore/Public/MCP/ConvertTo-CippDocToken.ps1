function ConvertTo-CippDocToken {
    <#
    .SYNOPSIS
        Tokenises text for the docs index: lowercase, split, de-stopped, lightly stemmed.
    .DESCRIPTION
        A thin wrapper over CIPPSharp's tokeniser, which is the single implementation. Indexing
        and querying must tokenise identically - a term indexed as 'standard' is never found by a
        query for 'Standards' otherwise - so there is deliberately no second copy of these rules
        in PowerShell. The rules themselves are documented on CIPP.DocsIndex.Tokenize.

        This exists so callers and tests can tokenise without reaching for the type name, and so
        the query path reads the same as the rest of the MCP code. Not an HTTP entrypoint.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text)

    return @([CIPP.DocsIndex]::Tokenize($Text))
}
