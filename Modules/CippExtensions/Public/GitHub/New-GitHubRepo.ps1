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
        private          = $Private.IsPresent
        license_template = $License
    }

    if ($Type -eq 'Org') {
        $Path = "orgs/$Org/repos"
        $Owner = $Org
    } else {
        $Path = 'user/repos'
        $Owner = (Invoke-GitHubApiRequest -Path 'user').login
    }

    # Check if repo exists
    try {
        $Existing = Invoke-GitHubApiRequest -Path "repos/$Owner/$Name"
        if ($Existing.id) {
            return $Existing
        }
    } catch { }
    if ($PSCmdlet.ShouldProcess("Create repository '$Name'")) {
        Invoke-GitHubApiRequest -Path $Path -Method POST -Body $Body
    }
}
