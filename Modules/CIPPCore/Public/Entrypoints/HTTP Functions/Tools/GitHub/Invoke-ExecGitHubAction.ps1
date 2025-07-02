function Invoke-ExecGitHubAction {
    <#
    .SYNOPSIS
    Execute GitHub API actions and repository operations
    
    .DESCRIPTION
    Performs various GitHub API operations including repository search, file operations, organization access, template imports, and repository creation through GitHub integration
    
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Extension.ReadWrite
        
    .NOTES
    Group: Tools
    Summary: Exec GitHub Action
    Description: Performs various GitHub API operations including repository search, file operations, organization access, template imports, and repository creation through GitHub integration with Personal Access Token (PAT) authentication
    Tags: Tools,GitHub,API,Repositories,Templates
    Parameter: Action (string) [query/body] - GitHub action to perform: Search, GetFileContents, GetBranches, GetOrgs, GetFileTree, ImportTemplate, CreateRepo
    Parameter: TenantFilter (string) [query/body] - Target tenant identifier
    Parameter: q (string) [query/body] - Search query for repository search
    Parameter: FullName (string) [query/body] - Repository full name (owner/repo) for file operations
    Parameter: Branch (string) [query/body] - Branch name for file operations
    Parameter: Path (string) [query/body] - File path for file operations
    Parameter: Name (string) [query/body] - Repository name for creation
    Parameter: Description (string) [query/body] - Repository description for creation
    Parameter: Private (boolean) [query/body] - Whether repository is private for creation
    Response: Returns an object with the following properties:
    Response: - Results (array/object): Results of the GitHub action
    Response: - Metadata (object): Additional metadata for search results (total_count, incomplete_results)
    Response: Actions performed:
    Response: - Search: Searches GitHub repositories and returns items with metadata
    Response: - GetFileContents: Retrieves file contents from a repository
    Response: - GetBranches: Lists branches in a repository
    Response: - GetOrgs: Lists organizations accessible to the authenticated user
    Response: - GetFileTree: Lists JSON files in a repository tree
    Response: - ImportTemplate: Imports community templates
    Response: - CreateRepo: Creates a new repository and stores it in CommunityRepos table
    Example: {
      "Results": [
        {
          "id": 123456789,
          "name": "cipp-standards",
          "full_name": "contoso/cipp-standards",
          "description": "CIPP Standards Repository",
          "html_url": "https://github.com/contoso/cipp-standards",
          "visibility": "public"
        }
      ],
      "Metadata": {
        "total_count": 1,
        "incomplete_results": false
      }
    }
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Action = $Request.Query.Action ?? $Request.Body.Action

    if ($Request.Query.Action) {
        $Parameters = $Request.Query
    }
    else {
        $Parameters = $Request.Body
    }

    $SplatParams = $Parameters | Select-Object -ExcludeProperty Action, TenantFilter | ConvertTo-Json | ConvertFrom-Json -AsHashtable

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).GitHub

    if (!$Configuration.Enabled) {
        $Response = Invoke-RestMethod -Uri 'https://cippy.azurewebsites.net/api/ExecGitHubAction' -Method POST -Body ($Parameters | ConvertTo-Json -Depth 10) -ContentType 'application/json'
        $Results = $Response.Results
        $Metadata = $Response.Metadata
    }
    else {
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
            'GetOrgs' {
                try {
                    $Orgs = Invoke-GitHubApiRequest -Path 'user/orgs'
                    $Results = @($Orgs)
                }
                catch {
                    $Results = @{
                        resultText = 'You may not have permission to view organizations, check your PAT scopes and try again - {0}' -f $_.Exception.Message
                        state      = 'error'
                    }
                }
            }
            'GetFileTree' {
                $Files = (Get-GitHubFileTree @SplatParams).tree | Where-Object { $_.path -match '.json$' } | Select-Object *, @{n = 'html_url'; e = { "https://github.com/$($SplatParams.FullName)/tree/$($SplatParams.Branch)/$($_.path)" } }
                $Results = @($Files)
            }
            'ImportTemplate' {
                $Results = Import-CommunityTemplate @SplatParams
            }
            'CreateRepo' {
                try {
                    Write-Information "Creating repository '$($SplatParams.Name)'"
                    $Repo = New-GitHubRepo @SplatParams
                    if ($Repo.id) {
                        $Table = Get-CIPPTable -TableName CommunityRepos
                        $RepoEntity = @{
                            PartitionKey  = 'CommunityRepos'
                            RowKey        = [string]$Repo.id
                            Name          = [string]($Repo.name -replace ' ', '-')
                            Description   = [string]$Repo.description
                            URL           = [string]$Repo.html_url
                            FullName      = [string]$Repo.full_name
                            Owner         = [string]$Repo.owner.login
                            Visibility    = [string]$Repo.visibility
                            WriteAccess   = [bool]$Repo.permissions.push
                            DefaultBranch = [string]$Repo.default_branch
                            Permissions   = [string]($Repo.permissions | ConvertTo-Json -Compress)
                        }
                        Add-CIPPAzDataTableEntity @Table -Entity $RepoEntity -Force | Out-Null

                        $Results = @{
                            resultText = "Repository '$($Repo.name)' created"
                            state      = 'success'
                        }
                    }
                }
                catch {
                    Write-Information (Get-CippException -Exception $_ | ConvertTo-Json)
                    $Results = @{
                        resultText = 'You may not have permission to create repositories, check your PAT scopes and try again - {0}' -f $_.Exception.Message
                        state      = 'error'
                    }
                }
            }
            default {
                $Results = @{
                    resultText = "Unknown action '$Action'"
                    state      = 'error'
                }
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
