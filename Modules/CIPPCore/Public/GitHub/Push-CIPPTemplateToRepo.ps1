function Push-CIPPTemplateToRepo {
    <#
    .SYNOPSIS
        Pushes a standards template to a community repository.
    .DESCRIPTION
        The body behind the UploadTemplate action of Invoke-ExecCommunityRepo, extracted so
        the save endpoints can push right after a save. On a successful push, stamps the
        templates row with the returned blob SHA and the repo FullName so the scheduled sync
        recognises this as the current copy instead of re-importing it as new.
    .OUTPUTS
        @{ resultText = <string>; state = 'success' | 'error' }
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$GUID,
        [Parameter(Mandatory)][string]$FullName,
        [string]$Message,
        [string]$Branch
    )

    $TemplateTable = Get-CIPPTable -TableName templates
    $TemplateEntity = Get-CIPPAzDataTableEntity @TemplateTable -Filter "RowKey eq '$($GUID)' or OriginalEntityId eq '$($GUID)'" | Select-Object -ExcludeProperty ETag, Timestamp
    if (-not $TemplateEntity) {
        return @{
            resultText = "Template '$($GUID)' not found"
            state      = 'error'
        }
    }

    if (-not $Branch) {
        $RepoTable = Get-CIPPTable -TableName CommunityRepos
        $RepoEntity = Get-CIPPAzDataTableEntity @RepoTable -Filter "PartitionKey eq 'CommunityRepos' and FullName eq '$($FullName)'"
        $Branch = $RepoEntity.UploadBranch ?? $RepoEntity.DefaultBranch
    }

    $Template = $TemplateEntity.JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop
    $DisplayName = $Template.Displayname ?? $Template.templateName ?? $Template.name
    if ($Template.tenantFilter) {
        $Template.tenantFilter = @(@{ label = 'Template Tenant'; value = 'Template Tenant' })
    }
    if ($Template.excludedTenants) {
        $Template.excludedTenants = @()
    }
    $TemplateEntity.JSON = $Template | ConvertTo-Json -Compress -Depth 100
    $ContentHash = Get-CIPPTemplateContentHash -JSON $TemplateEntity.JSON

    $Basename = $DisplayName -replace '\s', '_' -replace '[^\w\d_]', ''
    $Path = '{0}/{1}.json' -f $TemplateEntity.PartitionKey, $Basename
    # Pretty-printed, not compressed: repo files are hand-edited on GitHub.
    $PushResult = Push-GitHubContent -FullName $FullName -Path $Path -Content ($TemplateEntity | ConvertTo-Json -Depth 100) -Message $Message -Branch $Branch

    # A push that returns no blob sha did not land (integration disabled, or no write access).
    if (-not $PushResult.content.sha) {
        return @{
            resultText = "Template '$($DisplayName)' was not pushed to $FullName. Check the GitHub integration and that the repository is writable."
            state      = 'error'
        }
    }
    Add-CIPPAzDataTableEntity @TemplateTable -Entity @{
        PartitionKey = $TemplateEntity.PartitionKey
        RowKey       = $TemplateEntity.RowKey
        SHA          = [string]$PushResult.content.sha
        Source       = $FullName
        SourcePath   = $Path
        ContentHash  = $ContentHash
    } -OperationType UpsertMerge

    @{
        resultText = "Template '$($DisplayName)' uploaded"
        state      = 'success'
    }
}
