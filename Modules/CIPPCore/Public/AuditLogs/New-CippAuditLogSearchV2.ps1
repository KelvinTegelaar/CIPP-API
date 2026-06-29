function New-CippAuditLogSearchV2 {
    <#
    .SYNOPSIS
        Create a Microsoft Graph audit-log search for the V2 pipeline and return a classified result.
    .DESCRIPTION
        Thin wrapper over New-GraphPOSTRequest (which now honours 429 backoff). Unlike the V1
        New-CippAuditLogSearch, this writes to NO table - the AuditLogCoverage ledger is updated by
        the caller. Failures are classified so the caller can decide whether to retry (transient) or
        stop (auditing disabled).
    .PARAMETER TenantFilter
        Tenant default domain or customerId.
    .PARAMETER StartTime
        Window start (inclusive).
    .PARAMETER EndTime
        Window end (exclusive).
    .PARAMETER RecordTypeFilters
        Record types to capture. Defaults to the four the V1 pipeline used.
    .OUTPUTS
        [pscustomobject]@{ Id; Status; Outcome; Message }  Outcome in 'Created','AuditingDisabled','Transient'.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][datetime]$StartTime,
        [Parameter(Mandatory = $true)][datetime]$EndTime,
        [string[]]$RecordTypeFilters = @('exchangeAdmin', 'azureActiveDirectory', 'azureActiveDirectoryAccountLogon', 'azureActiveDirectoryStsLogon'),
        [int]$MaxAttempts = 3,
        [string]$DisplayName = ('CIPP Audit Search V2 - ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
    )

    $Body = @{
        displayName         = $DisplayName
        filterStartDateTime = $StartTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss')
        filterEndDateTime   = $EndTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss')
        recordTypeFilters   = @($RecordTypeFilters)
    } | ConvertTo-Json -Compress

    if (-not $PSCmdlet.ShouldProcess($TenantFilter, 'Create audit log search')) {
        return [pscustomobject]@{ Id = $null; Status = 'WhatIf'; Outcome = 'Transient'; Message = 'WhatIf'; Throttled = $false }
    }

    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
        try {
            # maxRetries 1 = no retry inside the Graph helper; this function owns retry/backoff.
            $Query = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/security/auditLog/queries' -body $Body -tenantid $TenantFilter -AsApp $true -maxRetries 1
            return [pscustomobject]@{ Id = $Query.id; Status = $Query.status; Outcome = 'Created'; Message = $null; Throttled = $false }
        } catch {
            $Raw = $_.Exception.Data['RawErrorBody']
            if (-not $Raw) { $Raw = $_.ErrorDetails.Message }
            if (-not $Raw) { $Raw = $_.Exception.Message }
            $Parsed = $null
            if ($Raw) { try { $Parsed = ([string]$Raw) | ConvertFrom-Json -ErrorAction Stop } catch {} }

            # AuditingDisabledTenant can be top-level Status or nested as JSON inside error.message.
            $AuditStatus = $Parsed.Status
            if (-not $AuditStatus) {
                $Inner = $Parsed.error.message ?? $Parsed.message
                if ($Inner -is [string]) { try { $AuditStatus = ($Inner | ConvertFrom-Json -ErrorAction Stop).Status } catch {} }
            }
            if ($AuditStatus -eq 'AuditingDisabledTenant') {
                return [pscustomobject]@{ Id = $null; Status = 'AuditingDisabledTenant'; Outcome = 'AuditingDisabled'; Message = 'Unified auditing is disabled for this tenant.'; Throttled = $false }
            }

            $Code = $Parsed.error.code ?? $Parsed.code
            $Msg = $Parsed.error.message ?? $Parsed.message ?? $_.Exception.Message
            $StatusCode = $null
            try { $StatusCode = [int]$_.Exception.Response.StatusCode } catch {}

            # 429 = the tenant's ~10 concurrent-search cap is full. Retrying in-process won't clear it,
            # so return immediately and let the planner defer this + remaining windows to next cycle.
            if (($Code -eq 'TooManyRequests') -or ($StatusCode -eq 429)) {
                return [pscustomobject]@{ Id = $null; Status = ([string]($Code ?? 'TooManyRequests')); Outcome = 'Transient'; Message = [string]$Msg; Throttled = $true }
            }

            # Other transient (UnknownError, 5xx, gateway, timeout): usually a momentary EXO-backend
            # blip that clears on a quick re-submit. Retry in-process with >1s jitter before giving up.
            if ($Attempt -lt $MaxAttempts) {
                Start-Sleep -Seconds (Get-Random -Minimum 1.5 -Maximum 4.0)
                continue
            }
            return [pscustomobject]@{ Id = $null; Status = ([string]($Code ?? 'Error')); Outcome = 'Transient'; Message = [string]$Msg; Throttled = $false }
        }
    }
}
