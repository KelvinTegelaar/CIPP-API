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
                PartitionKey = 'CommunityRepos'
                RowKey       = [string]$Repo.id
                Name         = [string]$Repo.name
                Description  = [string]$Repo.description
                URL          = [string]$Repo.html_url
                FullName     = [string]$Repo.full_name
                Owner        = [string]$Repo.owner.login
                Visibility   = [string]$Repo.visibility
                WriteAccess  = [bool]$Repo.permissions.push
                Permissions  = [string]($Repo.permissions | ConvertTo-Json -Compress)
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
                    PartitionKey = 'CommunityRepos'
                    RowKey       = [string]$Repo.id
                    Name         = [string]$Repo.name
                    Description  = [string]$Repo.description
                    URL          = [string]$Repo.html_url
                    FullName     = [string]$Repo.full_name
                    Owner        = [string]$Repo.owner.login
                    Visibility   = [string]$Repo.visibility
                    WriteAccess  = [bool]$Repo.permissions.push
                    Permissions  = [string]($Repo.permissions | ConvertTo-Json -Compress)
                    ETag         = $RepoEntity.ETag
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
