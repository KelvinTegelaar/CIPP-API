function Push-CIPPBaselineToRepo {
    <#
    .SYNOPSIS
        Pushes a baseline and its related templates to a community repository.
    .DESCRIPTION
        The body behind the UploadBaseline action of Invoke-ExecCommunityRepo, extracted so
        the save endpoints can push right after a save. A baseline is not a templates-table
        row: Export-CIPPBaselineTemplate assembles the portable set - the BaselineTemplate
        file plus one standard template file per referenced CA/Intune template. Every pushed
        file is stamped with its returned blob SHA and the repo FullName: related templates
        on their templates row, the baseline itself on its rollout row.
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

    if (-not $Branch) {
        $RepoTable = Get-CIPPTable -TableName CommunityRepos
        $RepoEntity = Get-CIPPAzDataTableEntity @RepoTable -Filter "PartitionKey eq 'CommunityRepos' and FullName eq '$($FullName)'"
        $Branch = $RepoEntity.UploadBranch ?? $RepoEntity.DefaultBranch
    }

    $Export = Export-CIPPBaselineTemplate -GUID $GUID
    if (-not $Export) {
        return @{
            resultText = "Baseline '$($GUID)' not found"
            state      = 'error'
        }
    }

    $TemplateTable = Get-CIPPTable -TableName templates
    foreach ($TemplateEntity in $Export.Templates) {
        $TemplateJson = $(try { $TemplateEntity.JSON | ConvertFrom-Json -Depth 100 } catch { $null })
        $DisplayName = "$($TemplateJson.Displayname ?? $TemplateJson.displayName ?? $TemplateJson.name ?? $TemplateEntity.RowKey)"
        $Basename = $DisplayName -replace '\s', '_' -replace '[^\w\d_]', ''
        $Path = '{0}/{1}.json' -f $TemplateEntity.PartitionKey, $Basename
        $PushResult = Push-GitHubContent -FullName $FullName -Path $Path -Content ($TemplateEntity | ConvertTo-Json -Depth 100) -Message $Message -Branch $Branch
        # A push that returns no blob sha did not land (integration disabled, or no write access).
        if (-not $PushResult.content.sha) {
            return @{
                resultText = "Template '$DisplayName' was not pushed to $FullName. Check the GitHub integration and that the repository is writable."
                state      = 'error'
            }
        }
        $TemplateStamp = @{
            PartitionKey = $TemplateEntity.PartitionKey
            RowKey       = $TemplateEntity.RowKey
            SHA          = [string]$PushResult.content.sha
            Source       = $FullName
            SourcePath   = $Path
        }
        # ContentHash powers hasLocalChanges, which is only exposed for standards templates.
        if ($TemplateEntity.PartitionKey -eq 'StandardsTemplateV2') {
            $TemplateStamp.ContentHash = Get-CIPPTemplateContentHash -JSON $TemplateEntity.JSON
        }
        Add-CIPPAzDataTableEntity @TemplateTable -Entity $TemplateStamp -OperationType UpsertMerge
    }

    $BaselineBasename = "$($Export.Baseline.templateName)" -replace '\s', '_' -replace '[^\w\d_]', ''
    $BaselinePath = 'BaselineTemplate/{0}.json' -f $BaselineBasename
    $BaselinePushResult = Push-GitHubContent -FullName $FullName -Path $BaselinePath -Content ($Export.Baseline | ConvertTo-Json -Depth 100) -Message $Message -Branch $Branch
    if (-not $BaselinePushResult.content.sha) {
        return @{
            resultText = "Baseline '$($Export.Baseline.templateName)' was not pushed to $FullName. Check the GitHub integration and that the repository is writable."
            state      = 'error'
        }
    }
    $RolloutTable = Get-CIPPTable -TableName BaselineRollouts
    Add-CIPPAzDataTableEntity @RolloutTable -Entity @{
        PartitionKey = 'rollout'
        RowKey       = "$GUID"
        SHA          = [string]$BaselinePushResult.content.sha
        Source       = $FullName
        SourcePath   = $BaselinePath
        LocalChanges = $false
    } -OperationType UpsertMerge

    @{
        resultText = "Baseline '$($Export.Baseline.templateName)' uploaded with $(@($Export.Templates).Count) related template$(if (@($Export.Templates).Count -eq 1) { '' } else { 's' })"
        state      = 'success'
    }
}
