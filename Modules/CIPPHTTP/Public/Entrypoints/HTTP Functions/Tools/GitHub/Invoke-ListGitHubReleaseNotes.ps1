function Invoke-ListGitHubReleaseNotes {
    <#
    .SYNOPSIS
        Retrieves release notes for a GitHub repository.
    .DESCRIPTION
        Returns release metadata for the provided repository. Results are cached and refreshed
        when the cache has no entry for the running version - hotfix releases (e.g. v8.5.2)
        publish their own notes, so a v8.5.0 entry no longer counts as current.
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Owner = 'CyberDrain'
    $Repository = 'CIPP'

    if (-not $Owner) {
        throw 'Owner parameter is required to retrieve release notes.'
    }

    if (-not $Repository) {
        throw 'Repository parameter is required to retrieve release notes.'
    }

    $ReleasePath = "repos/$Owner/$Repository/releases?per_page=50"

    $Table = Get-CIPPTable -TableName cacheGitHubReleaseNotes
    $PartitionKey = 'GitHubReleaseNotes'
    $Filter = "PartitionKey eq '$PartitionKey'"
    $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter

    try {
        $Latest = $false
        if ($Rows) {
            $CachedRow = $Rows | Select-Object -First 1
            $Releases = ConvertFrom-Json -InputObject $CachedRow.GitHubReleases -Depth 10
            $CurrentTag = 'v{0}' -f (($env:CippVersion ?? $env:APP_VERSION) -replace '^v', '')

            # Hotfixes publish their own release, so the cache is only current when it holds an
            # entry for the exact running version. Matching on major.minor kept serving v10.8.0's
            # notes to a v10.8.2 build forever, because the .0 release is always in the cache.
            $HasCurrentRelease = $null -ne ($Releases | Where-Object { $_.releaseTag -eq $CurrentTag } | Select-Object -First 1)

            # Versions with no release of their own (nightly, local, or a bump that lands before
            # the tag is published) would otherwise refetch on every page load, so they fall back
            # to a 15 minute floor instead of hammering the GitHub API.
            $MaxAge = $HasCurrentRelease ? (Get-Date).AddHours(-24) : (Get-Date).AddMinutes(-15)
            $Latest = $CachedRow.Timestamp -gt $MaxAge
        }

        if (-not $Latest) {
            $Releases = Invoke-GitHubApiRequest -Path $ReleasePath
            $Releases = $Releases | ForEach-Object {
                [ordered]@{
                    name        = $_.name
                    body        = $_.body
                    releaseTag  = $_.tag_name
                    htmlUrl     = $_.html_url
                    publishedAt = $_.published_at
                    draft       = [bool]$_.draft
                    prerelease  = [bool]$_.prerelease
                    commitish   = $_.target_commitish
                }
            }
            $Results = @{
                GitHubReleases = [string](ConvertTo-Json -Depth 10 -InputObject $Releases)
                RowKey         = [string]'GitHubReleaseNotes'
                PartitionKey   = $PartitionKey
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Results -Force | Out-Null
        }

    } catch {
        # A failed refresh shouldn't 500 the dialog when we still hold a cached catalog - serve
        # stale releases and let the log carry the reason the refresh failed.
        if (-not $Releases) {
            $ErrorMessage = "Failed to retrieve release information: $($_)"
            throw $ErrorMessage
        }
        Write-LogMessage -API 'GitHub' -tenant 'CIPP' -Sev 'Warning' -message "Failed to refresh GitHub release notes, serving cached releases instead. Error: $($_.Exception.Message)"
    }

    if (-not $Releases) {
        return $IsListRequest ? @() : (throw "No releases returned for $Owner/$Repository")
    }

    return $Releases
}
