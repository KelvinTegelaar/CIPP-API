function New-GitHubRepo {
    <#
    .SYNOPSIS
    Create a new GitHub repository

    .DESCRIPTION
    This function creates a new GitHub repository

    .PARAMETER Name
    The name of the repository

    .PARAMETER Description
    The description of the repository

    .PARAMETER Private
    Whether the repository is private

    .PARAMETER Type

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$Description,
        [switch]$Private,
        [ValidateSet('User', 'Org')]
        [string]$Type = 'User',
        [string]$Org,
        [string]$License = 'agpl-3.0'
    )

    $Body = @{
        name             = $Name
        description      = $Description
        private          = $Private
        license_template = $License
    }

    if ($Type -eq 'Org') {
        $Path = "orgs/$Org/repos"
    } else {
        $Path = 'user/repos'
    }

    if ($PSCmdlet.ShouldProcess("Create repository '$Name'")) {
        Invoke-GitHubApiRequest -Path $Path -Method POST -Body $Body
    }
}
