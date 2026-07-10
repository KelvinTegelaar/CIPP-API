function Invoke-ListAuditLogCoverage {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Alert.Read
    .DESCRIPTION
        Lists the V2 audit-log coverage ledger (AuditLogCoverage) - one row per tenant + 60-minute
        search window with its state (Planned / Created / Downloaded / Retry / DeadLetter / Skipped),
        record count, attempts and last error. Honours the tenant selector (a specific tenant or
        AllTenants) and CIPP tenant access control. Accepts the same date filters as the Saved Logs
        view: RelativeTime (e.g. 48h, 7d) or StartDate/EndDate. Defaults to the last 48 hours.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

    # --- Date range (mirrors Invoke-ListAuditLogs) ---
    $RelativeTime = $Request.Query.RelativeTime ?? $Request.Body.RelativeTime
    $StartDate = $Request.Query.StartDate ?? $Request.Body.StartDate
    $EndDate = $Request.Query.EndDate ?? $Request.Body.EndDate

    $EndUtc = (Get-Date).ToUniversalTime()
    $StartUtc = $EndUtc.AddHours(-48)

    if (-not $RelativeTime -and -not $StartDate -and -not $EndDate) {
        $RelativeTime = '48h'
    }

    if ($RelativeTime -and $RelativeTime -match '(\d+)([dhm])') {
        $Interval = [int]$Matches[1]
        switch ($Matches[2]) {
            'd' { $StartUtc = $EndUtc.AddDays(-$Interval) }
            'h' { $StartUtc = $EndUtc.AddHours(-$Interval) }
            'm' { $StartUtc = $EndUtc.AddMinutes(-$Interval) }
        }
    } elseif ($StartDate) {
        if ([string]$StartDate -match '^\d+$') {
            $StartUtc = [DateTimeOffset]::FromUnixTimeSeconds([int64]$StartDate).UtcDateTime
        } else {
            try { $StartUtc = ([datetimeoffset]$StartDate).UtcDateTime } catch {}
        }
        if ($EndDate) {
            if ([string]$EndDate -match '^\d+$') {
                $EndUtc = [DateTimeOffset]::FromUnixTimeSeconds([int64]$EndDate).UtcDateTime
            } else {
                try { $EndUtc = ([datetimeoffset]$EndDate).UtcDateTime } catch {}
            }
        }
    }

    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList

    # When access is scoped, resolve the caller's allowed tenants to both domain + id for matching.
    $AllowedDomains = $null
    $AllowedIds = $null
    if ($AllowedTenants -notcontains 'AllTenants') {
        $TenantList = Get-Tenants -IncludeErrors | Where-Object { $_.customerId -in $AllowedTenants }
        $AllowedDomains = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $AllowedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Tenant in $TenantList) {
            if ($Tenant.defaultDomainName) { [void]$AllowedDomains.Add([string]$Tenant.defaultDomainName) }
            if ($Tenant.customerId) { [void]$AllowedIds.Add([string]$Tenant.customerId) }
        }
    }

    function ConvertTo-Utc {
        param($Value)
        if (-not $Value) { return $null }
        try { return ([datetimeoffset]$Value).UtcDateTime } catch { return $null }
    }

    $Table = Get-CIPPTable -TableName 'AuditLogCoverage'
    $Rows = Get-CIPPAzDataTableEntity @Table

    $Results = foreach ($Row in $Rows) {
        $WindowStart = ConvertTo-Utc $Row.WindowStart
        # Date range filter on the window start
        if ($WindowStart) {
            if ($WindowStart -lt $StartUtc -or $WindowStart -gt $EndUtc) { continue }
        }

        # Tenant selector filter (match on default domain or customer id)
        if ($TenantFilter -and $TenantFilter -ne 'AllTenants') {
            if (($Row.PartitionKey -ne $TenantFilter) -and ([string]$Row.TenantId -ne [string]$TenantFilter)) { continue }
        }

        # Access control when not AllTenants
        if ($AllowedTenants -notcontains 'AllTenants') {
            if (-not ($AllowedDomains.Contains([string]$Row.PartitionKey) -or $AllowedIds.Contains([string]$Row.TenantId))) { continue }
        }

        [PSCustomObject]@{
            Tenant         = $Row.PartitionKey
            TenantId       = $Row.TenantId
            Type           = if ($Row.Type) { $Row.Type } elseif ($Row.RowKey -like 'RECON-*') { 'Reconciliation' } else { 'Window' }
            WindowStart    = $WindowStart
            WindowEnd      = ConvertTo-Utc $Row.WindowEnd
            State          = $Row.State
            RecordCount    = if ($null -ne $Row.RecordCount) { [int]$Row.RecordCount } else { $null }
            Attempts       = if ($null -ne $Row.Attempts) { [int]$Row.Attempts } else { 0 }
            RetryCount     = if ($null -ne $Row.RetryCount) { [int]$Row.RetryCount } else { 0 }
            ThrottleCount  = if ($null -ne $Row.ThrottleCount) { [int]$Row.ThrottleCount } else { 0 }
            SearchId       = $Row.SearchId
            SearchStatus   = $Row.SearchStatus
            NextAttemptUtc = ConvertTo-Utc $Row.NextAttemptUtc
            LastError      = $Row.LastError
            LastErrorUtc   = ConvertTo-Utc $Row.LastErrorUtc
            LastPolledUtc  = ConvertTo-Utc $Row.LastPolledUtc
            CreatedUtc     = ConvertTo-Utc $Row.CreatedUtc
            DownloadedUtc  = ConvertTo-Utc $Row.DownloadedUtc
            ProcessedUtc   = ConvertTo-Utc $Row.ProcessedUtc
            MatchedCount   = if ($null -ne $Row.MatchedCount) { [int]$Row.MatchedCount } else { $null }
            LastUpdated    = ConvertTo-Utc $Row.Timestamp
        }
    }

    $Results = @($Results | Sort-Object -Property @{ Expression = 'Tenant' }, @{ Expression = 'WindowStart'; Descending = $true })

    $Body = @{
        Results  = @($Results)
        Metadata = @{
            TenantFilter = $TenantFilter
            StartDate    = $StartUtc.ToString('o')
            EndDate      = $EndUtc.ToString('o')
            Total        = $Results.Count
        }
    } | ConvertTo-Json -Depth 10 -Compress

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
