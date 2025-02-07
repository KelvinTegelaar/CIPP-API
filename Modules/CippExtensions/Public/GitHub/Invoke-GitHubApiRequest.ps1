function Invoke-GitHubApiRequest {
    [CmdletBinding()]
    param(
        [string]$Method = 'GET',
        [Parameter(Mandatory = $true)]
        [string]
        $Path,
        [Parameter()]
        $Body,
        [string]$Accept = 'application/vnd.github+json',
        [switch]$ReturnHeaders
    )

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).GitHub

    if ($Configuration.Enabled) {
        $APIKey = Get-ExtensionAPIKey -Extension 'GitHub'
        $Headers = @{
            Authorization = "Bearer $($APIKey)"
            'User-Agent'  = 'CIPP'
            Accept        = $Accept
        }

        $FullUri = "https://api.github.com/$Path"
        Write-Verbose "[$Method] $FullUri"

        $RestMethod = @{
            Method  = $Method
            Uri     = $FullUri
            Headers = $Headers
        }
        if ($ReturnHeaders.IsPresent) {
            $RestMethod.ResponseHeadersVariable = 'ResponseHeaders'
        }

        $Response = Invoke-RestMethod @RestMethod
        if ($ReturnHeaders.IsPresent) {
            $ResponseHeaders
        } else {
            $Response
        }
    } else {
        throw 'GitHub API is not enabled'
    }
}
