function Invoke-ListGitHubReleaseNotes {
    <#
    .SYNOPSIS
        Retrieves release notes for a GitHub repository.
    .DESCRIPTION
        Returns release metadata for the provided repository and semantic version. Hotfix
        versions (e.g. v8.5.2) map back to the base release tag (v8.5.0).
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Owner = $Request.Query.Owner
    $Repository = $Request.Query.Repository

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
            $Releases = ConvertFrom-Json -InputObject $Rows.GitHubReleases -Depth 10
            $CurrentVersion = [semver]$global:CippVersion
            $CurrentMajorMinor = "$($CurrentVersion.Major).$($CurrentVersion.Minor)"

            foreach ($Release in $Releases) {
                $Version = $Release.releaseTag -replace 'v', ''
                try {
                    $ReleaseVersion = [semver]$Version
                    $ReleaseMajorMinor = "$($ReleaseVersion.Major).$($ReleaseVersion.Minor)"

                    # Check if we have cached notes for the current major.minor version series
                    if ($ReleaseMajorMinor -eq $CurrentMajorMinor) {
                        $Latest = $true
                        break
                    }
                } catch {
                    # Skip invalid semver versions
                    continue
                }
            }
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
        $ErrorMessage = "Failed to retrieve release information: $($_)"
        throw $ErrorMessage
    }

    if (-not $Releases) {
        return $IsListRequest ? @() : (throw "No releases returned for $Owner/$Repository")
    }

    return $Releases
}
