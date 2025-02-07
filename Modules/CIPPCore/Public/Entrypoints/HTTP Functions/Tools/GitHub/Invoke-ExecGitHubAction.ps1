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

    if ($Request.Body.Search) {
        $Search = $Request.Body.Search | ConvertTo-Json | ConvertFrom-Json -AsHashtable
        $SearchResults = Search-GitHub @Search
        $Results = $SearchResults.items
        $Metadata = $SearchResults | Select-Object -Property total_count, incomplete_results
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
