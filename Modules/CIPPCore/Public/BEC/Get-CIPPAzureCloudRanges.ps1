function Get-CIPPAzureCloudRanges {
    <#
    .SYNOPSIS
        Azure's public compute ranges (the AzureCloud service tag), as CIDRs.
    .DESCRIPTION
        Reads Microsoft's weekly Azure IP Ranges and Service Tags (Public cloud) file. AzureCloud covers
        every address an Azure customer can run code from, so a Microsoft-registered address outside it
        is operated by Microsoft itself rather than rented. The file's link changes with each weekly
        release, so it is read from the download page. The list is kept for a week in the
        CacheAzureServiceTags table; when the download fails an older cached copy is used, and with none
        at all this throws, so the caller decides how to degrade.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $Now = [datetime]::UtcNow
    if ($script:AzureCloudRanges -and $script:AzureCloudRanges.Expires -gt $Now) { return $script:AzureCloudRanges.Ranges }

    $Stale = $false
    $Table = Get-CIPPTable -TableName 'CacheAzureServiceTags'
    $Cached = try { Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'ServiceTags' and RowKey eq 'AzureCloud'" | Select-Object -First 1 } catch { $null }
    $CachedRanges = if ($Cached.JSON) { @($Cached.JSON | ConvertFrom-Json) } else { @() }
    $CachedAt = if ($Cached.Timestamp) { ([datetimeoffset]$Cached.Timestamp).UtcDateTime } else { [datetime]::MinValue }

    $Ranges = if ($CachedRanges.Count -gt 0 -and $CachedAt -gt $Now.AddDays(-7)) {
        $CachedRanges
    } else {
        try {
            $Page = Invoke-CIPPRestMethod -Uri 'https://www.microsoft.com/en-us/download/details.aspx?id=56519' -Method GET -TimeoutSec 20
            $Link = [regex]::Match([string]$Page, 'https://download\.microsoft\.com/download/[^"'']+?/ServiceTags_Public_\d+\.json').Value
            if (-not $Link) { throw 'The Azure service tags download page did not link a ServiceTags_Public file' }
            $Tags = Invoke-CIPPRestMethod -Uri $Link -Method GET -TimeoutSec 60
            # served as application/octet-stream with a byte order mark, so it arrives as text
            if ($Tags -is [string]) { $Tags = $Tags.TrimStart([char]0xFEFF) | ConvertFrom-Json -Depth 10 }
            $Fresh = @(($Tags.values | Where-Object { $_.name -eq 'AzureCloud' } | Select-Object -First 1).properties.addressPrefixes | Where-Object { $_ })
            if ($Fresh.Count -eq 0) { throw 'The Azure service tags file has no AzureCloud ranges' }
            try {
                Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'ServiceTags'; RowKey = 'AzureCloud'; Source = $Link; JSON = [string](ConvertTo-Json -InputObject $Fresh -Compress) } -Force
            } catch { Write-Information "Azure service tag cache write failed: $($_.Exception.Message)" }
            $Fresh
        } catch {
            if ($CachedRanges.Count -eq 0) { throw }
            $Stale = $true
            Write-Information "Azure service tags unavailable, using the copy from $($CachedAt.ToString('u')): $($_.Exception.Message)"
            $CachedRanges
        }
    }
    $script:AzureCloudRanges = [pscustomobject]@{ Expires = $(if ($Stale) { $Now.AddMinutes(10) } else { $Now.AddHours(6) }); Ranges = @($Ranges) }
    return @($Ranges)
}
