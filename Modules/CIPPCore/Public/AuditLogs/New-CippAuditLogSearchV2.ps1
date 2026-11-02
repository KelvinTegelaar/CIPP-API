function New-CippAuditLogSearchV2 {
    <#
    .SYNOPSIS
        Create Microsoft Graph audit-log searches for many tenants at once and return a classified result per search.
    .DESCRIPTION
        Each tenant's searches go in one Graph $batch and the tenants are sent concurrently
        (New-GraphMultiTenantBulkRequest). Writes to NO table - the AuditLogCoverage ledger is updated by the caller.
        Failures are classified so the caller can decide whether to retry (transient) or stop (auditing disabled,
        access denied). A 429 is the tenant's ~10 concurrent-search cap, so it is returned as Throttled and never
        re-sent here; other transient failures are re-sent up to -MaxAttempts times.
    .PARAMETER Searches
        One @{ TenantFilter; RowKey; StartTime; EndTime } per search. RowKey is passed through to the result.
    .PARAMETER RecordTypeFilters
        Record types to capture.
    .OUTPUTS
        One [pscustomobject]@{ TenantFilter; RowKey; Id; Status; Outcome; Message; Throttled } per search, in input
        order. Outcome is 'Created', 'AuditingDisabled', 'AccessDenied' or 'Transient'.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][object[]]$Searches,
        [string[]]$RecordTypeFilters = @('exchangeAdmin', 'azureActiveDirectory', 'azureActiveDirectoryAccountLogon', 'azureActiveDirectoryStsLogon'),
        [int]$MaxAttempts = 3,
        [string]$DisplayName = ('CIPP Audit Search V2 - ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
    )

    $Searches = @($Searches)
    if ($Searches.Count -eq 0) { return @() }
    $Results = [object[]]::new($Searches.Count)
    if (-not $PSCmdlet.ShouldProcess("$($Searches.Count) search(es)", 'Create audit log searches')) { return $Results }

    $Pending = @(0..($Searches.Count - 1))
    for ($Attempt = 1; $Attempt -le $MaxAttempts -and $Pending.Count -gt 0; $Attempt++) {
        # A momentary EXO-backend blip usually clears on a quick re-submit.
        if ($Attempt -gt 1) { Start-Sleep -Seconds (Get-Random -Minimum 1.5 -Maximum 4.0) }

        $ByTenant = [ordered]@{}
        foreach ($Index in $Pending) {
            $Search = $Searches[$Index]
            $Tenant = [string]$Search.TenantFilter
            if (-not $ByTenant.Contains($Tenant)) { $ByTenant[$Tenant] = [System.Collections.Generic.List[object]]::new() }
            $ByTenant[$Tenant].Add(@{
                    id      = [string]$Index
                    method  = 'POST'
                    url     = '/security/auditLog/queries'
                    headers = @{ 'Content-Type' = 'application/json' }
                    body    = @{
                        displayName         = $DisplayName
                        filterStartDateTime = ([datetime]$Search.StartTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss')
                        filterEndDateTime   = ([datetime]$Search.EndTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss')
                        recordTypeFilters   = @($RecordTypeFilters)
                    }
                })
        }
        $TenantRequests = foreach ($Tenant in $ByTenant.Keys) { @{ TenantFilter = $Tenant; Requests = $ByTenant[$Tenant].ToArray() } }
        $Sent = New-GraphMultiTenantBulkRequest -TenantRequests @($TenantRequests)

        $Retry = [System.Collections.Generic.List[int]]::new()
        foreach ($TenantResult in $Sent) {
            $Answered = @{}
            foreach ($Response in $TenantResult.Responses) { $Answered[[string]$Response.id] = $Response }
            foreach ($Request in $ByTenant[[string]$TenantResult.TenantFilter]) {
                $Index = [int]$Request.id
                $Response = $Answered[$Request.id]
                $Status = $Response.status -as [int]
                $Outcome = if ($Status -ge 200 -and $Status -lt 300 -and $Response.body.id) {
                    @{ Id = [string]$Response.body.id; Status = [string]$Response.body.status; Outcome = 'Created'; Message = $null; Throttled = $false }
                } elseif (-not $TenantResult.Error -and -not $Response) {
                    @{ Status = 'Error'; Outcome = 'Transient'; Message = 'No response for this search in the batch reply'; Throttled = $false }
                } else {
                    $Raw = if ($TenantResult.Error) { [string]$TenantResult.Error } elseif ($Response.body -is [string]) { $Response.body } else { [CIPP.CippJson]::ToJson($Response.body, 20) ?? (ConvertTo-Json -InputObject $Response.body -Compress -Depth 20) }
                    $Parsed = $null
                    if ($Raw) { try { $Parsed = $Raw | ConvertFrom-Json -ErrorAction Stop } catch {} }
                    # AuditingDisabledTenant can be top-level Status or nested as JSON inside error.message.
                    $AuditStatus = $Parsed.Status
                    if (-not $AuditStatus) {
                        $Inner = $Parsed.error.message ?? $Parsed.message
                        if ($Inner -is [string]) { try { $AuditStatus = ($Inner | ConvertFrom-Json -ErrorAction Stop).Status } catch {} }
                    }
                    $Code = $Parsed.error.code ?? $Parsed.code
                    $Throttled = $Code -eq 'TooManyRequests' -or $Status -eq 429
                    # AADSTS7000229: CIPP's service principal is missing. "dont have any permissions": the tenant never consented.
                    if ($Raw -match 'AADSTS7000229') {
                        @{ Status = 'MissingServicePrincipal'; Outcome = 'AccessDenied'; Message = $Raw; Throttled = $false }
                    } elseif ($Raw -match "don'?t have any permissions") {
                        @{ Status = 'MissingPermissions'; Outcome = 'AccessDenied'; Message = 'CIPP does not have the required permissions to search the audit log in this tenant.'; Throttled = $false }
                    } elseif ($AuditStatus -eq 'AuditingDisabledTenant') {
                        @{ Status = 'AuditingDisabledTenant'; Outcome = 'AuditingDisabled'; Message = 'Unified auditing is disabled for this tenant.'; Throttled = $false }
                    } else {
                        @{ Status = [string]($Code ?? $(if ($Throttled) { 'TooManyRequests' } else { 'Error' })); Outcome = 'Transient'; Message = [string]($Parsed.error.message ?? $Parsed.message ?? $Raw); Throttled = $Throttled }
                    }
                }
                $Results[$Index] = [pscustomobject]@{
                    TenantFilter = $Searches[$Index].TenantFilter
                    RowKey       = $Searches[$Index].RowKey
                    Id           = $Outcome.Id
                    Status       = $Outcome.Status
                    Outcome      = $Outcome.Outcome
                    Message      = $Outcome.Message
                    Throttled    = $Outcome.Throttled
                }
                if ($Outcome.Outcome -eq 'Transient' -and -not $Outcome.Throttled) { $Retry.Add($Index) }
            }
        }
        $Pending = $Retry.ToArray()
    }
    return $Results
}
