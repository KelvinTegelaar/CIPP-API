function Push-CIPPTemplateToRepo {
    <#
    .SYNOPSIS
        Pushes a standards template to a community repository.
    .DESCRIPTION
        The body behind the UploadTemplate action of Invoke-ExecCommunityRepo, extracted so
        the save endpoints can push right after a save. On a successful push, stamps the
        templates row with the returned blob SHA and the repo FullName so the scheduled sync
        recognises this as the current copy instead of re-importing it as new.
        Templates it links by GUID (Get-CIPPTemplateLink) are pushed first, and the main file
        carries a LinkedTemplates manifest (JSON: partition, guid, path) so an import brings them.
    .OUTPUTS
        @{ resultText = <string>; state = 'success' | 'error' }. Throws ItemNotFoundException when the template does not exist.
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
        throw [System.Management.Automation.ItemNotFoundException]::new("Template '$($GUID)' not found")
    }

    if (-not $Branch) {
        $RepoTable = Get-CIPPTable -TableName CommunityRepos
        $RepoEntity = Get-CIPPAzDataTableEntity @RepoTable -Filter "PartitionKey eq 'CommunityRepos' and FullName eq '$($FullName)'"
        $Branch = $RepoEntity.UploadBranch ?? $RepoEntity.DefaultBranch
    }

    # Pushes one templates row and stamps it with the returned blob SHA; LinkedTemplates rides along on the main file only
    $PushEntity = {
        param($Entity, $LinkedTemplates)
        $Template = $Entity.JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop
        $EntityName = $Template.Displayname ?? $Template.templateName ?? $Template.name
        if ($Template.tenantFilter) {
            $Template.tenantFilter = @(@{ label = 'Template Tenant'; value = 'Template Tenant' })
        }
        if ($Template.excludedTenants) {
            $Template.excludedTenants = @()
        }
        $Entity.JSON = $Template | ConvertTo-Json -Compress -Depth 100
        $ContentHash = Get-CIPPTemplateContentHash -JSON $Entity.JSON
        $Basename = $EntityName -replace '\s', '_' -replace '[^\w\d_]', ''
        $Path = '{0}/{1}.json' -f $Entity.PartitionKey, $Basename
        $File = if ($LinkedTemplates) { $Entity | Select-Object *, @{ n = 'LinkedTemplates'; e = { ConvertTo-Json -Compress -Depth 5 -InputObject @($LinkedTemplates) } } } else { $Entity }
        # Pretty-printed, not compressed: repo files are hand-edited on GitHub.
        $PushResult = Push-GitHubContent -FullName $FullName -Path $Path -Content ($File | ConvertTo-Json -Depth 100) -Message $Message -Branch $Branch
        # A push that returns no blob sha did not land (integration disabled, or no write access).
        if ($PushResult.content.sha) {
            Add-CIPPAzDataTableEntity @TemplateTable -Entity @{
                PartitionKey = $Entity.PartitionKey
                RowKey       = $Entity.RowKey
                SHA          = [string]$PushResult.content.sha
                Source       = $FullName
                SourcePath   = $Path
                ContentHash  = $ContentHash
            } -OperationType UpsertMerge
        }
        [pscustomobject]@{ Name = $EntityName; Path = $Path; Pushed = [bool]$PushResult.content.sha }
    }

    # Templates this one links by GUID go to the repo first, so an import can bring them along
    $Linked = [System.Collections.Generic.List[object]]::new()
    $Seen = @{ "$($TemplateEntity.PartitionKey)|$($TemplateEntity.RowKey)" = $true }
    $Queue = [System.Collections.Generic.Queue[object]]::new()
    $Queue.Enqueue($TemplateEntity)
    while ($Queue.Count -gt 0) {
        $Entity = $Queue.Dequeue()
        foreach ($Link in @(Get-CIPPTemplateLink -PartitionKey $Entity.PartitionKey -Template ($Entity.JSON | ConvertFrom-Json -Depth 100))) {
            $Key = "$($Link.Partition)|$($Link.Ref)"
            if ($Seen.ContainsKey($Key)) { continue }
            $Seen[$Key] = $true
            $Row = Get-CIPPAzDataTableEntity @TemplateTable -Filter "PartitionKey eq '$($Link.Partition)' and RowKey eq '$(ConvertTo-CIPPODataFilterValue -Value $Link.Ref -Type String)'" | Select-Object -First 1 -ExcludeProperty ETag, Timestamp
            if (-not $Row) {
                Write-Information "Push-CIPPTemplateToRepo: linked $($Link.Partition) '$($Link.Label)' ($($Link.Ref)) no longer exists - not pushed."
                continue
            }
            $Linked.Add($Row)
            $Queue.Enqueue($Row)
        }
    }
    $Manifest = [System.Collections.Generic.List[object]]::new()
    foreach ($Row in $Linked) {
        $Pushed = & $PushEntity $Row $null
        if (-not $Pushed.Pushed) {
            return @{
                resultText = "Template '$($Pushed.Name)', which this template links, was not pushed to $FullName, so neither was this template. Check the GitHub integration and that the repository is writable."
                state      = 'error'
            }
        }
        $Manifest.Add([pscustomobject]@{ partition = $Row.PartitionKey; guid = $Row.RowKey; path = $Pushed.Path })
    }

    $Main = & $PushEntity $TemplateEntity $Manifest
    $DisplayName = $Main.Name
    if (-not $Main.Pushed) {
        return @{
            resultText = "Template '$($DisplayName)' was not pushed to $FullName. Check the GitHub integration and that the repository is writable."
            state      = 'error'
        }
    }

    @{
        resultText = "Template '$($DisplayName)' uploaded$(if ($Manifest.Count) { " with $($Manifest.Count) linked template(s)" })"
        state      = 'success'
    }
}
