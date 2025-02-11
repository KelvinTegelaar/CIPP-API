function Invoke-ExecGitHubAction {
    <#
    .SYNOPSIS
        Invoke GitHub Action
    .DESCRIPTION
        Call GitHub API
    .ROLE
        CIPP.Extension.ReadWrite
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Action = $Request.Query.Action ?? $Request.Body.Action

    if ($Request.Query.Action) {
        $Parameters = $Request.Query
    } else {
        $Parameters = $Request.Body
    }

    $SplatParams = $Parameters | Select-Object -ExcludeProperty Action, TenantFilter | ConvertTo-Json | ConvertFrom-Json -AsHashtable

    $Extensionsconfig = Get-CippTable -tablename 'Extensionsconfig'
    $Extensions = $Extensionsconfig | Where-Object { $_.PartitionKey -eq 'Extensionsconfig' } | Select-Object -ExpandProperty JSON | ConvertFrom-Json
    $GitHubEnabled = $Extensions.GitHub.enabled

    if (-not $GitHubEnabled) {
        $Response = Invoke-RestMethod -Uri 'https://cippy.azurewebsites.net/api/ExecGitHubAction' -Method POST -Body ($Action | ConvertTo-Json -Depth 10) -ContentType 'application/json'
        $Results = $Response.Results
        $Metadata = $Response.Metadata
    } else {
        switch ($Action) {
            'Search' {
                $SearchResults = Search-GitHub @SplatParams
                $Results = @($SearchResults.items)
                $Metadata = $SearchResults | Select-Object -Property total_count, incomplete_results
            }
            'GetFileContents' {
                $Results = Get-GitHubFileContents @SplatParams
            }
            'GetBranches' {
                $Results = @(Get-GitHubBranch @SplatParams)
            }
            'GetFileTree' {
                $Files = (Get-GitHubFileTree @SplatParams).tree | Where-Object { $_.path -match '.json$' } | Select-Object *, @{n = 'html_url'; e = { "https://github.com/$($SplatParams.FullName)/tree/$($SplatParams.Branch)/$($_.path)" } }
                $Results = @($Files)
            }
            'ImportTemplate' {
                $Results = Import-CommunityTemplate @SplatParams
            }
        }
    }

    $Body = @{
        Results = $Results
    }
    if ($Metadata) {
        $Body.Metadata = $Metadata
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
