function Invoke-ListCommunityRepoTemplates {
    <#
    .SYNOPSIS
        List templates available in community repositories
    .DESCRIPTION
        Builds a catalog of templates across community repositories using a single git tree call
        per repository. Joins against the templates table to flag imported templates and available
        updates. When a Path is supplied, returns the contents of that single file instead (preview).
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Preview mode: return the contents of a single file
    if ($Request.Query.Path) {
        try {
            $Branch = $Request.Query.Branch
            if (!$Branch) { $Branch = 'main' }
            $File = Get-GitHubFileContents -FullName $Request.Query.FullName -Path $Request.Query.Path -Branch $Branch
            $Body = @{ Results = $File }
        } catch {
            $Body = @{
                Results = @(@{
                        resultText = "Unable to retrieve file contents: $($_.Exception.Message)"
                        state      = 'error'
                    })
            }
        }
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $Body
            })
    }

    $Table = Get-CIPPTable -TableName CommunityRepos
    $Repos = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CommunityRepos'"

    if (!$Repos) {
        # First call on a fresh instance before ListCommunityRepos has seeded the table
        $CommunityRepos = Join-Path $env:CIPPRootPath 'Config\CommunityRepos.json'
        $Repos = [System.IO.File]::ReadAllText($CommunityRepos) | ConvertFrom-Json | ForEach-Object {
            [PSCustomObject]@{
                Name          = $_.Name
                FullName      = $_.FullName
                DefaultBranch = $_.DefaultBranch
                TemplateTypes = [string](ConvertTo-Json -InputObject @($_.TemplateTypes) -Compress)
            }
        }
    }

    if ($Request.Query.FullName) {
        $Repos = $Repos | Where-Object { $_.FullName -eq $Request.Query.FullName }
    }

    # Community-imported template rows carry Source (repo FullName) and SHA (git blob sha),
    # which lets us mark imported/update-available without any extra GitHub calls.
    $TemplatesTable = Get-CippTable -tablename 'templates'
    $ImportedTemplates = foreach ($Row in (Get-CIPPAzDataTableEntity @TemplatesTable)) {
        if ([string]::IsNullOrEmpty($Row.Source)) { continue }
        $Name = $null
        try {
            $Data = $Row.JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop
            $Name = $Data.displayName ?? $Data.Displayname ?? $Data.templateName ?? $Data.name
        } catch {
            # Name matching is best-effort; SHA matching still works without it
        }
        [PSCustomObject]@{
            Source        = $Row.Source
            SHA           = $Row.SHA
            SanitizedName = if ($Name) { ($Name -replace '\s', '_' -replace '[^\w\d_]', '') } else { $null }
        }
    }

    # Folder names in CIPP-native repos are templates-table PartitionKeys ("Save to GitHub"
    # writes {PartitionKey}/{Name}.json), so these folder names reliably identify the type.
    $KnownPartitionKeys = @(
        'IntuneTemplate', 'CATemplate', 'StandardsTemplate', 'StandardsTemplateV2', 'GroupTemplate',
        'AppApprovalTemplate', 'ReportBuilderTemplate', 'BPATemplate', 'TransportTemplate',
        'ExConnectorTemplate', 'AppTemplate', 'ContactTemplate', 'JITAdminTemplate',
        'UserDefaultTemplate', 'AssignmentFilterTemplate', 'IntuneReusableSettingTemplate',
        'SharePointTemplate', 'DlpCompliancePolicyTemplate', 'RetentionCompliancePolicyTemplate',
        'SensitivityLabelTemplate', 'SensitiveInfoTypeTemplate'
    )

    $Warnings = [System.Collections.Generic.List[string]]::new()
    $CatalogItems = [System.Collections.Generic.List[object]]::new()
    $RepoMetadata = [System.Collections.Generic.List[object]]::new()

    foreach ($Repo in $Repos) {
        $Branch = $Repo.DefaultBranch
        if ([string]::IsNullOrEmpty($Branch)) { $Branch = 'main' }
        try {
            $Tree = Get-GitHubFileTree -FullName $Repo.FullName -Branch $Branch
            if ($Tree.truncated) {
                $Warnings.Add("File list for $($Repo.FullName) was truncated by GitHub; some templates may be missing.")
            }

            # One extra call per repository (not per file) for the branch head commit
            try {
                $BranchInfo = Invoke-GitHubApiRequest -Path "repos/$($Repo.FullName)/branches/$Branch"
                $RepoMetadata.Add([PSCustomObject]@{
                        FullName            = $Repo.FullName
                        LatestCommitMessage = [string](($BranchInfo.commit.commit.message -split "`n")[0])
                        LatestCommitDate    = [string]$BranchInfo.commit.commit.author.date
                        LatestCommitUrl     = [string]$BranchInfo.commit.html_url
                    })
            } catch {
                # Commit info is decorative; the catalog works without it
            }

            $RepoTypes = @(($Repo.TemplateTypes | ConvertFrom-Json -ErrorAction SilentlyContinue) ?? @())
            $BySha = @{}
            $ByName = @{}
            foreach ($Imported in $ImportedTemplates) {
                if ($Imported.Source -ne $Repo.FullName) { continue }
                if ($Imported.SHA) { $BySha[$Imported.SHA] = $true }
                if ($Imported.SanitizedName) { $ByName[$Imported.SanitizedName] = $true }
            }

            foreach ($File in $Tree.tree) {
                if ($File.path -notmatch '\.json$' -or $File.path -match 'NativeImport') { continue }
                $FileName = (($File.path -split '/')[-1]) -replace '\.json$', ''
                if ($FileName -eq 'MigrationTable' -or $FileName -match 'ALLOWED COUNTRIES') { continue }

                $Segments = $File.path -split '/'
                $Folders = @($Segments | Select-Object -SkipLast 1)
                $TopFolder = $Folders | Select-Object -First 1

                # Type resolution: CIPP-native repos use templates-table PartitionKeys as folder
                # names; otherwise the type belongs to the repository record. Multi-type repos
                # keep their declared types as PossibleTypes so type-scoped views still match.
                $PossibleTypes = @()
                if ($TopFolder -and $KnownPartitionKeys -contains $TopFolder) {
                    $Type = $TopFolder
                    $CategoryFolders = @($Folders | Select-Object -Skip 1)
                } elseif ($TopFolder -eq 'CustomTests') {
                    $Type = 'CustomTest'
                    $CategoryFolders = @($Folders | Select-Object -Skip 1)
                } elseif ($RepoTypes.Count -eq 1) {
                    $Type = $RepoTypes[0]
                    $CategoryFolders = $Folders
                } else {
                    $Type = 'Other'
                    $PossibleTypes = $RepoTypes
                    $CategoryFolders = $Folders
                }
                $Category = if ($CategoryFolders.Count -gt 0) { $CategoryFolders -join ' / ' } else { 'General' }

                $SanitizedFileName = ($FileName -replace '\s', '_' -replace '[^\w\d_]', '')
                $Imported = $false
                $UpdateAvailable = $false
                if ($BySha.ContainsKey($File.sha)) {
                    $Imported = $true
                } elseif ($ByName.ContainsKey($SanitizedFileName)) {
                    $Imported = $true
                    $UpdateAvailable = $true
                }

                $CatalogItems.Add([PSCustomObject]@{
                        Repository      = $Repo.FullName
                        RepositoryName  = $Repo.Name
                        Path            = $File.path
                        DisplayName     = ($FileName -replace '_', ' ')
                        Category        = $Category
                        Type            = $Type
                        PossibleTypes   = @($PossibleTypes)
                        SHA             = $File.sha
                        Size            = $File.size
                        Branch          = $Branch
                        HtmlUrl         = "https://github.com/$($Repo.FullName)/blob/$Branch/$($File.path)"
                        Imported        = $Imported
                        UpdateAvailable = $UpdateAvailable
                    })
            }
        } catch {
            $Warnings.Add("Unable to list templates for $($Repo.FullName): $($_.Exception.Message)")
        }
    }

    $Body = @{
        Results  = @($CatalogItems)
        Metadata = @{
            Warnings     = @($Warnings)
            Repositories = @($RepoMetadata)
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
