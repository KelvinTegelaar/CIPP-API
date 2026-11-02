function Get-CIPPBecRogueAppFeed {
    <#
    .SYNOPSIS
        Returns the merged rogue-application catalog (CIPP MaliciousApps.json + Huntress rogueapps) keyed by appId.
    .DESCRIPTION
        The Huntress feed (https://huntresslabs.github.io/rogueapps/rogueapps.json) is fetched with a
        short timeout and memoised per worker for an hour, so bulk BEC runs do not hit GitHub Pages once
        per user. CIPP's own curated list is always merged in; when the feed is unavailable the result
        says so (HuntressAvailable = $false) and the curated list alone is used - a feed outage must
        never fail a run or read as "no rogue apps".
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $Now = (Get-Date).ToUniversalTime()
    if ($script:CippBecRogueAppMemo -and $script:CippBecRogueAppMemo.Expires -gt $Now) {
        return $script:CippBecRogueAppMemo.Feed
    }

    $Apps = @{}
    $HuntressAvailable = $false
    $HuntressUpdated = $null
    $HuntressApps = @()
    try {
        $Feed = Invoke-RestMethod -Uri 'https://huntresslabs.github.io/rogueapps/rogueapps.json' -TimeoutSec 10 -ErrorAction Stop
        # A GitHub Pages error page parses without throwing, so check the shape too.
        if (@($Feed).Where({ $_.appId }, 'First')) {
            $HuntressApps = @($Feed | Where-Object { $_.appId } | Select-Object appId, appDisplayName, description, tags, references, dateAdded)
            $HuntressAvailable = $true
            $HuntressUpdated = $Now.ToString('o')
        }
    } catch {
        Write-Information "BEC rogue app feed: Huntress feed unavailable: $($_.Exception.Message)"
    }

    foreach ($App in $HuntressApps) {
        if (-not $App.appId) { continue }
        $Apps[([string]$App.appId).ToLowerInvariant()] = [pscustomobject]@{
            Name        = $App.appDisplayName
            Description = $App.description
            Categories  = @()
            Tags        = @($App.tags)
            References  = @($App.references)
            Added       = $App.dateAdded
            Source      = 'Huntress'
        }
    }

    try {
        $CippApps = @((Get-Content -Path (Join-Path $env:CIPPRootPath 'Config\MaliciousApps.json') -ErrorAction Stop | ConvertFrom-Json).applications)
        foreach ($App in $CippApps) {
            if (-not $App.appId) { continue }
            $Key = ([string]$App.appId).ToLowerInvariant()
            # CIPP's entries carry categories and richer descriptions; they win over the feed copy.
            $Apps[$Key] = [pscustomobject]@{
                Name        = $App.name
                Description = $App.description
                Categories  = @($App.categories)
                Tags        = @($App.tags)
                References  = @($App.references)
                Added       = $null
                Source      = if ($Apps.ContainsKey($Key)) { 'CIPP, Huntress' } else { 'CIPP' }
            }
        }
    } catch {
        Write-Information "BEC rogue app feed: could not load MaliciousApps.json: $($_.Exception.Message)"
    }

    $Result = [pscustomobject]@{
        Apps              = $Apps
        Count             = $Apps.Count
        HuntressAvailable = [bool]$HuntressAvailable
        HuntressUpdated   = $HuntressUpdated
    }
    $script:CippBecRogueAppMemo = @{ Feed = $Result; Expires = $Now.AddHours(1) }
    return $Result
}
