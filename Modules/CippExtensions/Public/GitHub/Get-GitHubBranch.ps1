function Get-GitHubBranch {
    <#
    .SYNOPSIS
        Get GitHub Branch
    .DESCRIPTION
        Get GitHub Branch
    .
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FullName
    )

    Invoke-GitHubApiRequest -Path "repos/$FullName/branches" -Method GET
}
