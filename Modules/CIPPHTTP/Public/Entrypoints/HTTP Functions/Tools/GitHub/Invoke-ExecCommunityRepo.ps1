function Invoke-ExecCommunityRepo {
    <#
    .SYNOPSIS
        Make changes to a community repository
    .DESCRIPTION
        This function makes changes to a community repository in table storage
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Action = $Request.Body.Action
    $Id = $Request.Body.Id
    if ($Request.Body.Id) {
        $Filter = "PartitionKey eq 'CommunityRepos' and RowKey eq '$($Id)'"
    } elseif ($Request.Body.FullName) {
        $Filter = "PartitionKey eq 'CommunityRepos' and FullName eq '$($Request.Body.FullName)'"
    } else {
        $Results = @(
            @{
                resultText = 'Id or FullName required'
                state      = 'error'
            }
        )
        $Body = @{
            Results = $Results
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $Body
            })
        return
    }

    $Table = Get-CIPPTable -TableName CommunityRepos
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
                resultText = "Repository $($RepoEntity.Name) deleted"
                state      = 'success'
            }
        }
        'UploadTemplate' {
            $GUID = $Request.Body.GUID
            $TemplateTable = Get-CIPPTable -TableName templates
            $TemplateEntity = Get-CIPPAzDataTableEntity @TemplateTable -Filter "RowKey eq '$($GUID)'" | Select-Object -ExcludeProperty ETag, Timestamp
            $Branch = $RepoEntity.UploadBranch ?? $RepoEntity.DefaultBranch
            if ($TemplateEntity) {
                $Template = $TemplateEntity.JSON | ConvertFrom-Json
                $DisplayName = $Template.Displayname ?? $Template.templateName ?? $Template.name
                if ($Template.tenantFilter) {
                    $Template.tenantFilter = @(@{ label = 'Template Tenant'; value = 'Template Tenant' })
                }
                if ($Template.excludedTenants) {
                    $Template.excludedTenants = @()
                }
                $TemplateEntity.JSON = $Template | ConvertTo-Json -Compress -Depth 100

                $Basename = $DisplayName -replace '\s', '_' -replace '[^\w\d_]', ''
                $Path = '{0}/{1}.json' -f $TemplateEntity.PartitionKey, $Basename
                $Results = Push-GitHubContent -FullName $Request.Body.FullName -Path $Path -Content ($TemplateEntity | ConvertTo-Json -Compress) -Message $Request.Body.Message -Branch $Branch

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
        'SetBranch' {
            if (!$RepoEntity) {
                $Results = @{
                    resultText = "Repository $($Id) not found"
                    state      = 'error'
                }
            } else {
                $Branch = $Request.Body.Branch
                if (!$RepoEntity.UploadBranch) {
                    $RepoEntity | Add-Member -NotePropertyName 'UploadBranch' -NotePropertyValue $Branch
                } else {
                    $RepoEntity.UploadBranch = $Branch
                }
                $null = Add-CIPPAzDataTableEntity @Table -Entity $RepoEntity -Force

                $Results = @{
                    resultText = "Branch set to $Branch"
                    state      = 'success'
                }
            }
        }
        'ImportTemplate' {
            $Path = $Request.Body.Path
            $FullName = $Request.Body.FullName
            $Branch = $Request.Body.Branch
            try {
                $Template = Get-GitHubFileContents -FullName $FullName -Path $Path -Branch $Branch

                $Content = $Template.content | ConvertFrom-Json
                if ($Content.'@odata.type' -like '*conditionalAccessPolicy*') {
                    $Files = (Get-GitHubFileTree -FullName $FullName -Branch $Branch).tree | Where-Object { $_.path -match '.json$' -and $_.path -notmatch 'NativeImport' } | Select-Object *, @{n = 'html_url'; e = { "https://github.com/$($SplatParams.FullName)/tree/$($SplatParams.Branch)/$($_.path)" } }, @{n = 'name'; e = { ($_.path -split '/')[ -1 ] -replace '\.json$', '' } }

                    $MigrationTable = $Files | Where-Object { $_.name -eq 'MigrationTable' } | Select-Object -Last 1
                    if ($MigrationTable) {
                        Write-Host "Found a migration table, getting contents for $FullName"
                        $MigrationTable = (Get-GitHubFileContents -FullName $FullName -Branch $Branch -Path $MigrationTable.path).content | ConvertFrom-Json
                    }

                    $NamedLocations = $Files | Where-Object { $_.name -match 'ALLOWED COUNTRIES' }
                    $LocationData = foreach ($Location in $NamedLocations) {
                        (Get-GitHubFileContents -FullName $FullName -Branch $Branch -Path $Location.path).content | ConvertFrom-Json
                    }
                }
                $ImportResult = Import-CommunityTemplate -Template $Content -SHA $Template.sha -MigrationTable $MigrationTable -LocationData $LocationData -Source $FullName

                $Results = @{
                    resultText = $ImportResult ?? 'Template imported'
                    state      = 'success'
                }
            } catch {
                $Results = @{
                    resultText = "Error importing template: $($_.Exception.Message)"
                    state      = 'error'
                }
            }
        }
        'UploadScript' {
            $ScriptGuid = $Request.Body.GUID
            $ScriptTable = Get-CippTable -tablename 'CustomPowershellScripts'
            $ScriptFilter = "PartitionKey eq 'CustomScript' and ScriptGuid eq '$($ScriptGuid)'"
            $ScriptVersions = @(Get-CIPPAzDataTableEntity @ScriptTable -Filter $ScriptFilter)
            $Branch = $RepoEntity.UploadBranch ?? $RepoEntity.DefaultBranch

            if ($ScriptVersions.Count -gt 0) {
                $LatestScript = $ScriptVersions | Sort-Object -Property Version -Descending | Select-Object -First 1
                $ExportData = @{
                    ScriptName           = $LatestScript.ScriptName
                    ScriptContent        = $LatestScript.ScriptContent
                    Description          = $LatestScript.Description
                    Category             = $LatestScript.Category
                    Risk                 = $LatestScript.Risk
                    Pillar               = $LatestScript.Pillar
                    ImplementationEffort = $LatestScript.ImplementationEffort
                    UserImpact           = $LatestScript.UserImpact
                    ReturnType           = $LatestScript.ReturnType
                    MarkdownTemplate     = $LatestScript.MarkdownTemplate
                    ResultSchema         = $LatestScript.ResultSchema
                    ResultMode           = $LatestScript.ResultMode
                }

                $Basename = $LatestScript.ScriptName -replace '\s', '_' -replace '[^\w\d_]', ''
                $Path = 'CustomTests/{0}.json' -f $Basename
                $null = Push-GitHubContent -FullName $Request.Body.FullName -Path $Path -Content ($ExportData | ConvertTo-Json -Compress -Depth 10) -Message $Request.Body.Message -Branch $Branch

                $Results = @{
                    resultText = "Custom test '$($LatestScript.ScriptName)' uploaded"
                    state      = 'success'
                }
            } else {
                $Results = @{
                    resultText = "Custom test '$($ScriptGuid)' not found"
                    state      = 'error'
                }
            }
        }
        'ImportScript' {
            $Path = $Request.Body.Path
            $FullName = $Request.Body.FullName
            $Branch = $Request.Body.Branch
            try {
                $FileContent = Get-GitHubFileContents -FullName $FullName -Path $Path -Branch $Branch
                $ScriptData = $FileContent.content | ConvertFrom-Json

                if (-not $ScriptData.ScriptName -or -not $ScriptData.ScriptContent) {
                    throw 'Invalid custom test file: ScriptName and ScriptContent are required'
                }

                Test-CustomScriptSecurity -ScriptContent $ScriptData.ScriptContent

                $ScriptTable = Get-CippTable -tablename 'CustomPowershellScripts'
                $ScriptGuid = (New-Guid).ToString()
                $Version = 1
                $RowKey = '{0}-v{1}' -f $ScriptGuid, $Version

                $Entity = @{
                    PartitionKey         = 'CustomScript'
                    RowKey               = $RowKey
                    ScriptGuid           = $ScriptGuid
                    ScriptName           = $ScriptData.ScriptName
                    Version              = $Version
                    ScriptContent        = $ScriptData.ScriptContent
                    Description          = $ScriptData.Description ?? ''
                    Category             = $ScriptData.Category ?? ''
                    Risk                 = $ScriptData.Risk ?? 'Medium'
                    Pillar               = $ScriptData.Pillar ?? 'Identity'
                    ImplementationEffort = $ScriptData.ImplementationEffort ?? 'Medium'
                    UserImpact           = $ScriptData.UserImpact ?? 'Low'
                    Enabled              = $false
                    AlertOnFailure       = $false
                    ReturnType           = $ScriptData.ReturnType ?? 'JSON'
                    MarkdownTemplate     = $ScriptData.MarkdownTemplate ?? ''
                    ResultSchema         = $ScriptData.ResultSchema ?? ''
                    ResultMode           = $ScriptData.ResultMode ?? 'Auto'
                    CreatedBy            = 'GitHub Import'
                    CreatedDate          = (Get-Date).ToUniversalTime().ToString('o')
                }

                Add-CIPPAzDataTableEntity @ScriptTable -Entity $Entity -Force

                $Results = @{
                    resultText = "Custom test '$($ScriptData.ScriptName)' imported (disabled by default)"
                    state      = 'success'
                }
            } catch {
                $Results = @{
                    resultText = "Error importing custom test: $($_.Exception.Message)"
                    state      = 'error'
                }
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

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
