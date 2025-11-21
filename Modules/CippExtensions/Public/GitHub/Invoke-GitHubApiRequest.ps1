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
    $ExtensionConfig = (Get-CIPPAzDataTableEntity @Table).config
    if ($ExtensionConfig -and (Test-Json -Json $ExtensionConfig)) {
        $Configuration = ($ExtensionConfig | ConvertFrom-Json).GitHub
    } else {
        $Configuration = @{ Enabled = $false }
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
            throw $_.Exception.Message
        }
    } else {
        $Action = @{
            Action = 'ApiCall'
            Path   = $Path
            Method = $Method
            Body   = $Body
            Accept = $Accept
        }
        $Body = $Action | ConvertTo-Json -Depth 10

        (Invoke-RestMethod -Uri 'https://cippy.azurewebsites.net/api/ExecGitHubAction' -Method POST -Body $Body -ContentType 'application/json').Results
    }
}
