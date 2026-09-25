function Invoke-ExecCommunityRepo {
    <#
    .SYNOPSIS
        Make changes to a community repository
    .DESCRIPTION
        This function makes changes to a community repository in table storage
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.TemplateLibrary.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

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
            try {
                if ($Id) {
                    $Repo = Invoke-GitHubApiRequest -Path "repositories/$($Id)"
                } else {
                    $Repo = Invoke-GitHubApiRequest -Path "repos/$($Request.Body.FullName)"
                }
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
                if ($Request.Body.TemplateTypes) {
                    $RepoEntity.TemplateTypes = [string](ConvertTo-Json -InputObject @($Request.Body.TemplateTypes) -Compress)
                }

                Add-CIPPAzDataTableEntity @Table -Entity $RepoEntity -Force | Out-Null

                $Results = @{
                    resultText = "Community repository '$($Repo.name)' added"
                    state      = 'success'
                }
            } catch {
                $Results = @{
                    resultText = "Unable to add repository: $($_.Exception.Message)"
                    state      = 'error'
                }
            }
        }
        'SetTemplateTypes' {
            if (!$RepoEntity) {
                $Results = @{
                    resultText = "Repository $($Id) not found"
                    state      = 'error'
                }
            } else {
                $TemplateTypesJson = [string](ConvertTo-Json -InputObject @($Request.Body.TemplateTypes) -Compress)
                $RepoEntity | Add-Member -NotePropertyName 'TemplateTypes' -NotePropertyValue $TemplateTypesJson -Force
                $null = Add-CIPPAzDataTableEntity @Table -Entity $RepoEntity -Force

                $Results = @{
                    resultText = "Template types updated for $($RepoEntity.Name)"
                    state      = 'success'
                }
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
                Remove-CIPPAzDataTableEntity @Table -Entity $Delete
            }
            $Results = @{
                resultText = "Repository $($RepoEntity.Name) deleted"
                state      = 'success'
            }
        }
        'UploadTemplate' {
            $Branch = $RepoEntity.UploadBranch ?? $RepoEntity.DefaultBranch
            $Results = Push-CIPPTemplateToRepo -GUID $Request.Body.GUID -FullName $Request.Body.FullName -Message $Request.Body.Message -Branch $Branch
        }
        'UploadBaseline' {
            # A baseline is not a templates-table row: Export-CIPPBaselineTemplate
            # assembles the portable set - the BaselineTemplate file plus one standard
            # template file per referenced CA/Intune template (packages expanded to
            # their current members). Related templates are separate files, exactly the
            # shape UploadTemplate writes, so they import through the untouched path.
            $Branch = $RepoEntity.UploadBranch ?? $RepoEntity.DefaultBranch
            $Results = Push-CIPPBaselineToRepo -GUID $Request.Body.GUID -FullName $Request.Body.FullName -Message $Request.Body.Message -Branch $Branch
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
            $Force = [bool]$Request.Body.Force
            try {
                $Template = Get-GitHubFileContents -FullName $FullName -Path $Path -Branch $Branch

                $Content = $Template.content | ConvertFrom-Json
                if ($Content.TemplateType -eq 'BaselineTemplate') {
                    # Baseline files carry a referencedTemplates manifest: the importer
                    # fetches every related template from this repo first (the same
                    # related-items pattern as CA named locations), then creates the
                    # baseline itself. Never a templates-table write.
                    $User = $(try { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } catch { $null })
                    $ImportResult = Import-CIPPBaselineTemplate -Baseline $Content -FullName $FullName -Branch $Branch -SHA $Template.sha -Path $Path -User $User -Force:$Force
                    $Results = @{
                        resultText = $ImportResult ?? 'Baseline imported'
                        state      = 'success'
                    }
                } else {
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
                    $ImportResult = Import-CommunityTemplate -Template $Content -SHA $Template.sha -MigrationTable $MigrationTable -LocationData $LocationData -Source $FullName -Path $Path -Force:$Force

                    $Results = @{
                        resultText = $ImportResult ?? 'Template imported'
                        state      = 'success'
                    }
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
                $null = Push-GitHubContent -FullName $Request.Body.FullName -Path $Path -Content ($ExportData | ConvertTo-Json -Depth 10) -Message $Request.Body.Message -Branch $Branch

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

    if ($Results) {
        if ($Results.state -eq 'success') {
            Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Results.resultText -Sev 'Info'
        } elseif ($Results.state -eq 'error') {
            Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Results.resultText -Sev 'Error'
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
