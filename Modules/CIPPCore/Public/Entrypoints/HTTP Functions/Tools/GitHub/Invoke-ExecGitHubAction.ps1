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

    #Write-Information ($SplatParams | ConvertTo-Json)

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
