function Invoke-GitHubApiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Configuration,
        [string]$Method = 'GET',
        [Parameter(Mandatory = $true)]
        [string]
        $Path,
        [Parameter()]
        $Body
    )

    if ($Configuration.Enabled) {
        $APIKey = Get-ExtensionAPIKey -Extension 'GitHub'
        $Headers = @{
            Authorization = "Bearer $($APIKey)"
            'User-Agent'  = 'CIPP'
            Accept        = 'application/vnd.github.v3+json'
        }

        $FullUri = "https://api.github.com/$Path"
        return Invoke-RestMethod -Method $Method -Uri $FullUri -Headers $Headers -Body $Body
    } else {
        throw 'GitHub API is not enabled'
    }
}
