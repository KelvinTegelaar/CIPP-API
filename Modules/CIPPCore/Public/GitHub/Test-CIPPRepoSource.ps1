function Test-CIPPRepoSource {
    <#
    .SYNOPSIS
        True when a template's Source column names a GitHub repository (owner/repo).
    .DESCRIPTION
        The Source column is also used for other provenance markers, such as the baseline
        migration's 'StandardsTemplateV2:<guid>' and tenant-sourced templates, which must not
        read as repository syncs.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([string]$Source)

    return ($Source -match '^[\w.-]+/[\w.-]+$')
}
