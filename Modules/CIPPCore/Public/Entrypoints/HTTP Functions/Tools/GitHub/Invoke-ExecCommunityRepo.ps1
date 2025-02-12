function Invoke-ExecCommunityRepo {
    <#
    .SYNOPSIS
        Make changes to a community repository
    .DESCRIPTION
        This function makes changes to a community repository in table storage
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Action = $Request.Body.Action
    $Id = $Request.Body.Id

    $Table = Get-CIPPTable -TableName CommunityRepos
    $Filter = "PartitionKey eq 'CommunityRepos' and RowKey eq '$($Id)'"
    $RepoEntity = Get-CIPPAzDataTableEntity @Table -Filter $Filter

    switch ($Action) {
        'Add' {
            $Repo = Invoke-GitHubApiRequest -Path "repositories/$($Id)"
            $RepoEntity = @{
                PartitionKey  = 'CommunityRepos'
                RowKey        = [string]$Repo.id
                Name          = [string]$Repo.name
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
                resultText = "Community repository '$($Repo.name)' added"
                state      = 'success'
            }
        }
        'Update' {
            if ($RepoEntity) {
                $Repo = Invoke-GitHubApiRequest -Path "repositories/$($Id)"
                $Update = @{
                    PartitionKey  = 'CommunityRepos'
                    RowKey        = [string]$Repo.id
                    Name          = [string]$Repo.name
                    Description   = [string]$Repo.description
                    URL           = [string]$Repo.html_url
                    FullName      = [string]$Repo.full_name
                    Owner         = [string]$Repo.owner.login
                    Visibility    = [string]$Repo.visibility
                    WriteAccess   = [bool]$Repo.permissions.push
                    DefaultBranch = [string]$Repo.default_branch
                    Permissions   = [string]($Repo.permissions | ConvertTo-Json -Compress)
                    ETag          = $RepoEntity.ETag
                }

                Update-CIPPAzDataTableEntity @Table -Entity $Update

                $Results = @{
                    resultText = "Repository $($Repo.name) updated"
                    state      = 'success'
                }
            } else {
                $Results = @{
                    resultText = "Repository $($Repo.name) not found"
                    state      = 'error'
                }
            }
        }
        'Delete' {
            if ($RepoEntity) {
                $Delete = $RepoEntity | Select-Object PartitionKey, RowKey, ETag
                Remove-AzDataTableEntity @Table -Entity $Delete
            }
            $Results = @{
                resultText = "Repository $($Repo.name) deleted"
                state      = 'success'
            }
        }
        'UploadTemplate' {
            $GUID = $Request.Body.GUID
            $TemplateTable = Get-CIPPTable -TableName templates
            $TemplateEntity = Get-CIPPAzDataTableEntity @TemplateTable -Filter "RowKey eq '$($GUID)'"
            if ($TemplateEntity) {
                $Template = $TemplateEntity.JSON | ConvertFrom-Json
                $DisplayName = $Template.Displayname ?? $Template.templateName ?? $Template.name
                $Basename = $DisplayName -replace '\s', '_' -replace '[^\w\d_]', ''
                $Path = '{0}/{1}.json' -f $TemplateEntity.PartitionKey, $Basename
                $Results = Push-GitHubContent -FullName $Request.Body.FullName -Path $Path -Content ($TemplateEntity | ConvertTo-Json -Compress) -Message $Request.Body.Message

                $Results = @{
                    resultText = "Template '$($DisplayName)' uploaded"
                    state      = 'success'
                }
            } else {
                $Results = @{
                    resultText = "Template '$($GUID)' not found"
                    state      = 'error'
                }
            }
        }
        'ImportTemplate' {
            $Path = $Request.Body.Path
            $FullName = $Request.Body.FullName
            $Branch = $Request.Body.Branch
            $Template = Get-GitHubFileContents -FullName $FullName -Path $Path -Branch $Branch
            Import-CommunityTemplate -Template $Template
        }
        default {
            $Results = @{
                resultText = "Action $Action not supported"
                state      = 'error'
            }
        }
    }

    $Body = @{
        Results = @($Results)
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
