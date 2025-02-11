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

        try {
            $Response = Invoke-RestMethod @RestMethod
            if ($ReturnHeaders.IsPresent) {
                $ResponseHeaders
            } else {
                $Response
            }
        } catch {
            Write-Error $_.Exception.Message
        }
    } else {
        $Action = @{
            Action = 'ApiCall'
            Path   = $Path
            Method = $Method
            Body   = $Body
            Accept = $Accept
        }
        (Invoke-RestMethod -Uri 'https://cippy.azurewebsites.net/api/ExecGitHubAction' -Method POST -Body ($Action | ConvertTo-Json -Depth 10) -ContentType 'application/json').Results
    }
}
