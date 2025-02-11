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
    $SplatParams = ($Request.Query ?? $Request.Body) | Select-Object -ExcludeProperty Action, TenantFilter | ConvertTo-Json | ConvertFrom-Json -AsHashtable

    switch ($Action) {
        'Search' {
            $Results = (Search-GitHub @SplatParams).items
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
