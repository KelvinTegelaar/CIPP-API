function Get-CIPPTemplateSourceUrl {
    <#
    .SYNOPSIS
        Builds the GitHub URL for a synced template's source file.
    .DESCRIPTION
        The frontend cannot guess a template's repo path: the scheduled sync matches
        files by sanitised filename anywhere in the tree, so the path is only known at
        import/push time and stored as SourcePath. This resolves the branch to link
        against from the CommunityRepos row (UploadBranch, falling back to
        DefaultBranch, then 'main').
    .OUTPUTS
        string or $null
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$Source,
        [string]$SourcePath,
        [array]$Repos
    )

    if ([string]::IsNullOrEmpty($Source)) { return $null }

    if (-not $Repos) {
        $RepoTable = Get-CIPPTable -TableName CommunityRepos
        $Repos = @(Get-CIPPAzDataTableEntity @RepoTable -Filter "PartitionKey eq 'CommunityRepos'")
    }
    $RepoEntity = $Repos | Where-Object { $_.FullName -eq $Source } | Select-Object -First 1
    $Branch = $RepoEntity.UploadBranch ?? $RepoEntity.DefaultBranch ?? 'main'

    if ([string]::IsNullOrEmpty($SourcePath)) {
        return "https://github.com/$Source"
    }
    "https://github.com/$Source/blob/$Branch/$SourcePath"
}
