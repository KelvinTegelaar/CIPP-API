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
        [switch]$ReturnHeaders,
        # Skip the anonymous function-app fallback so token failures surface to the caller -
        # the test endpoint needs the real verdict on the configured PAT, not a masked success.
        [switch]$NoFallback
    )

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $ExtensionConfig = (Get-CIPPAzDataTableEntity @Table).config
    if ($ExtensionConfig -and (Test-Json -Json $ExtensionConfig)) {
        $Configuration = ($ExtensionConfig | ConvertFrom-Json).GitHub
    } else {
        $Configuration = @{ Enabled = $false }
    }

    function Invoke-GitHubFunctionAppRequest {
        param($Method, $Path, $Body, $Accept)
        $Action = @{
            Action = 'ApiCall'
            Path   = $Path
            Method = $Method
            Body   = $Body
            Accept = $Accept
        }
        $ActionBody = $Action | ConvertTo-Json -Depth 10
        (Invoke-RestMethod -Uri 'https://cippy.azurewebsites.net/api/ExecGitHubAction' -Method POST -Body $ActionBody -ContentType 'application/json').Results
    }

    if ($Configuration.Enabled) {
        $APIKey = Get-ExtensionAPIKey -Extension 'GitHub'
        $Headers = @{
            Authorization          = "Bearer $($APIKey)"
            'User-Agent'           = 'CIPP'
            Accept                 = $Accept
            'X-GitHub-API-Version' = '2022-11-28'
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

        if ($Body) {
            $RestMethod.Body = $Body | ConvertTo-Json -Depth 10
            $RestMethod.ContentType = 'application/json'
        }

        try {
            $Response = Invoke-RestMethod @RestMethod
            if ($ReturnHeaders.IsPresent) {
                $Response | Add-Member -MemberType NoteProperty -Name Headers -Value $ResponseHeaders
                return $Response
            } else {
                return $Response
            }
        } catch {
            # A bad or rate-limited PAT shouldn't take down read paths the function app can serve
            # anonymously. Writes stay on the PAT - the function app would run them as its own
            # identity, not the user's.
            $StatusCode = $_.Exception.Response.StatusCode.value__
            if ($StatusCode -in 401, 403, 429) {
                Write-LogMessage -API 'GitHub' -tenant 'CIPP' -Sev 'Error' -message "GitHub rejected the configured API token (status $StatusCode) for [$Method] $Path. Verify the GitHub integration API key is valid and has not expired. Error: $($_.Exception.Message)"
                if ($Method -eq 'GET' -and -not $NoFallback) {
                    return Invoke-GitHubFunctionAppRequest -Method $Method -Path $Path -Body $Body -Accept $Accept
                }
            }
            throw $_.Exception.Message
        }
    } else {
        Invoke-GitHubFunctionAppRequest -Method $Method -Path $Path -Body $Body -Accept $Accept
    }
}
