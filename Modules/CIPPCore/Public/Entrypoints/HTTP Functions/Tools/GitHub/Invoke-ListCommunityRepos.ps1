function Invoke-ListCommunityRepos {
    <#
    .SYNOPSIS
    List community repositories from GitHub integration
    
    .DESCRIPTION
    Retrieves a list of community repositories from Table Storage with optional filtering and default repository management
    
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
        
    .NOTES
    Group: Tools
    Summary: List Community Repos
    Description: Retrieves a list of community repositories from Table Storage with support for write access filtering and automatic default repository management
    Tags: Tools,GitHub,Community
    Parameter: WriteAccess (boolean) [query] - Filter repositories to only show those with write access
    Response: Returns a response object with the following properties:
    Response: - Results (array): Array of repository objects with the following properties:
    Response: - Id (string): Repository unique identifier
    Response: - Name (string): Repository name
    Response: - Description (string): Repository description
    Response: - URL (string): Repository URL
    Response: - FullName (string): Repository full name (owner/repo)
    Response: - Owner (string): Repository owner
    Response: - Visibility (string): Repository visibility (public, private)
    Response: - WriteAccess (boolean): Whether write access is available
    Response: - DefaultBranch (string): Default branch name
    Response: - UploadBranch (string): Branch used for uploads
    Response: - RepoPermissions (object): Repository permissions configuration
    Example: {
      "Results": [
        {
          "Id": "cipp-standards",
          "Name": "CIPP Standards",
          "Description": "Community-driven security standards for Microsoft 365",
          "URL": "https://github.com/community/cipp-standards",
          "FullName": "community/cipp-standards",
          "Owner": "community",
          "Visibility": "public",
          "WriteAccess": true,
          "DefaultBranch": "main",
          "UploadBranch": "main",
          "RepoPermissions": {
            "admin": true,
            "push": true,
            "pull": true
          }
        }
      ]
    }
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CIPPTable -TableName CommunityRepos

    if ($Request.Query.WriteAccess -eq 'true') {
        $Filter = "PartitionKey eq 'CommunityRepos' and WriteAccess eq true"
    }
    else {
        $Filter = ''
    }

    $Repos = Get-CIPPAzDataTableEntity @Table -Filter $Filter

    if (!$Request.Query.WriteAccess) {
        $CIPPRoot = (Get-Item (Get-Module -Name CIPPCore).ModuleBase).Parent.Parent.FullName
        $CommunityRepos = Join-Path -Path $CIPPRoot -ChildPath 'CommunityRepos.json'
        $DefaultCommunityRepos = Get-Content -Path $CommunityRepos -Raw | ConvertFrom-Json

        $DefaultsMissing = $false
        foreach ($Repo in $DefaultCommunityRepos) {
            if ($Repos.Url -notcontains $Repo.Url) {
                $Entity = [PSCustomObject]@{
                    PartitionKey  = 'CommunityRepos'
                    RowKey        = $Repo.Id
                    Name          = $Repo.Name
                    Description   = $Repo.Description
                    URL           = $Repo.URL
                    FullName      = $Repo.FullName
                    Owner         = $Repo.Owner
                    Visibility    = $Repo.Visibility
                    WriteAccess   = $Repo.WriteAccess
                    DefaultBranch = $Repo.DefaultBranch
                    UploadBranch  = $Repo.DefaultBranch
                    Permissions   = [string]($Repo.RepoPermissions | ConvertTo-Json)
                }
                Add-CIPPAzDataTableEntity @Table -Entity $Entity
                $DefaultsMissing = $true
            }
        }
        if ($DefaultsMissing) {
            $Repos = Get-CIPPAzDataTableEntity @Table
        }
    }

    $Repos = $Repos | ForEach-Object {
        [pscustomobject]@{
            Id              = $_.RowKey
            Name            = $_.Name
            Description     = $_.Description
            URL             = $_.URL
            FullName        = $_.FullName
            Owner           = $_.Owner
            Visibility      = $_.Visibility
            WriteAccess     = $_.WriteAccess
            DefaultBranch   = $_.DefaultBranch
            UploadBranch    = $_.UploadBranch ?? $_.DefaultBranch
            RepoPermissions = $_.Permissions | ConvertFrom-Json
        }
    }

    $Body = @{
        Results = @($Repos | Sort-Object -Property FullName)
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
