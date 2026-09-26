function Get-CIPPMicrosoft365IPRanges {
    <#
    .SYNOPSIS
        Microsoft 365's published service address ranges (IPv4 and IPv6 CIDRs).
    .DESCRIPTION
        Reads the worldwide Microsoft 365 endpoint list (endpoints.office.com IP web service) - the
        front ends of Exchange Online, SharePoint, Teams and the identity service. Traffic from these
        addresses is Microsoft acting for the user (on-behalf-of token exchanges, proxied clients,
        mailbox access through the service), never a machine an attacker can rent: rented Azure
        compute sits on Microsoft's network (AS8075) but outside these ranges.
        The list is kept for a day in the CacheM365IPRanges table (a worker recycle clears the
        in-process memo in front of it). When the web service cannot be read, an older cached copy is
        used; with none at all this throws, so the caller decides how to degrade.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $Now = [datetime]::UtcNow
    if ($script:M365IPRanges -and $script:M365IPRanges.Expires -gt $Now) { return $script:M365IPRanges.Ranges }

    $Stale = $false
    $Table = Get-CIPPTable -TableName 'CacheM365IPRanges'
    $Cached = try { Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'M365' and RowKey eq 'worldwide'" | Select-Object -First 1 } catch { $null }
    $CachedRanges = if ($Cached.JSON) { @($Cached.JSON | ConvertFrom-Json) } else { @() }
    $CachedAt = if ($Cached.Timestamp) { ([datetimeoffset]$Cached.Timestamp).UtcDateTime } else { [datetime]::MinValue }

    $Ranges = if ($CachedRanges.Count -gt 0 -and $CachedAt -gt $Now.AddDays(-1)) {
        $CachedRanges
    } else {
        try {
            # the web service asks for one stable client id per caller: the instance's app id is exactly that
            $ClientId = [guid]::Empty
            if (-not [guid]::TryParse([string]$env:ApplicationID, [ref]$ClientId)) { $ClientId = [guid]::NewGuid() }
            $Response = Invoke-CIPPRestMethod -Uri "https://endpoints.office.com/endpoints/worldwide?clientrequestid=$ClientId" -Method GET -TimeoutSec 20
            $Fresh = @($Response.ips | Where-Object { $_ } | Select-Object -Unique)
            if ($Fresh.Count -eq 0) { throw 'The Microsoft 365 endpoint list returned no address ranges' }
            try {
                Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'M365'; RowKey = 'worldwide'; JSON = [string](ConvertTo-Json -InputObject $Fresh -Compress) } -Force
            } catch { Write-Information "Microsoft 365 range cache write failed: $($_.Exception.Message)" }
            $Fresh
        } catch {
            if ($CachedRanges.Count -eq 0) { throw }
            $Stale = $true
            Write-Information "Microsoft 365 range list unavailable, using the copy from $($CachedAt.ToString('u')): $($_.Exception.Message)"
            $CachedRanges
        }
    }
    # a stale fallback is only memoised briefly, so the next case retries the web service
    $script:M365IPRanges = [pscustomobject]@{ Expires = $(if ($Stale) { $Now.AddMinutes(10) } else { $Now.AddHours(1) }); Ranges = @($Ranges) }
    return @($Ranges)
}
