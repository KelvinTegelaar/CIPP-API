function Get-GitHubFileTree {
    <#
    .SYNOPSIS
        Get GitHub File Tree
    .DESCRIPTION
        Get GitHub File Tree
    .
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FullName,
        [Parameter(Mandatory = $true)]
        [string]$Branch
    )

    Invoke-GitHubApiRequest -Path "repos/$FullName/git/trees/$($Branch)?recursive=1" -Method GET
}
