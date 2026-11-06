function Invoke-CIPPDBCacheCollection {
    <#
    .SYNOPSIS
        Execute a grouped collection of DB cache functions for a tenant

    .DESCRIPTION
        Runs all Set-CIPPDBCache* functions belonging to a collection type sequentially
        within a single invocation. This reduces orchestrator activity count by ~10x
        compared to individual per-type activities, eliminating replay overhead.

        Collection types map to license categories:
        - Graph:                Core tenant data (no special license needed)
        - ExchangeConfig:       Exchange Online policy/config data
        - ExchangeData:         Mailboxes, CAS mailboxes, usage reports
        - ConditionalAccess:    CA policies, registration details and app credential, role and grant changes (Entra ID P1)
        - IdentityProtection:   Risky users/SPs, risk detections (Entra ID P2)
        - PIM:                  Role eligibility, assignment schedules, role policies (P2 or ID Governance)
        - Intune:               Managed devices, policies, app protection
        - DefenderForOffice365: Safe Links/Attachments, ATP, Teams protection (MDO P1/P2)
        - Defender:             Defender for Endpoint vulnerabilities (TVM/CVE)

    .PARAMETER CollectionType
        The group of cache functions to execute

    .PARAMETER TenantFilter
        The tenant domain to collect data for

    .PARAMETER QueueId
        Optional queue ID for progress tracking

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Graph', 'ExchangeConfig', 'ExchangeData', 'ConditionalAccess', 'IdentityProtection', 'PIM', 'Intune', 'Compliance', 'CopilotUsage', 'SharePoint', 'Teams', 'DefenderForOffice365', 'Defender')]
        [string]$CollectionType,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [string]$QueueId
    )

    $CacheTypes = (Get-CIPPDBCacheSchedule)[$CollectionType].Types
    if (-not $CacheTypes -or $CacheTypes.Count -eq 0) {
        throw "Unknown or empty collection type: $CollectionType"
    }

    Write-Information "Starting $CollectionType collection for $TenantFilter ($($CacheTypes.Count) cache types)"

    $CollectionStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $SuccessCount = 0
    $FailedCount = 0
    $Errors = [System.Collections.Generic.List[string]]::new()
    $Timings = [System.Collections.Generic.List[string]]::new()

    if ($CollectionType -eq 'Intune') {
        # Start the report exports early; DetectedApps, IntuneAppInstallStatus and IntuneNonCompliantSettings read them last
        foreach ($ReportName in 'AppInvRawData', 'AppInstallStatusAggregate', 'NoncompliantDevicesAndSettingsV3') {
            try { $null = Get-CIPPIntuneReportExportJob -TenantFilter $TenantFilter -ReportName $ReportName }
            catch { Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Could not start the $ReportName export: $($_.Exception.Message)" -sev Warning -LogData (Get-CippException -Exception $_) }
        }
    }

    foreach ($CacheType in $CacheTypes) {
        $FullFunctionName = "Set-CIPPDBCache$CacheType"
        $ItemStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $Function = Get-Command -Name $FullFunctionName -ErrorAction SilentlyContinue
            if (-not $Function) {
                throw "Function $FullFunctionName not found"
            }

            $Params = @{ TenantFilter = $TenantFilter }
            if ($QueueId) { $Params.QueueId = $QueueId }
            # IntunePolicies runs earlier in this group and has already written the shared group snapshot
            if ($Function.Parameters.Keys -contains 'SkipGroupSnapshot') { $Params.SkipGroupSnapshot = $true }

            Write-Information "  [$CollectionType] Collecting $CacheType for $TenantFilter"
            & $FullFunctionName @Params
            $ItemStopwatch.Stop()
            $ElapsedSeconds = '{0:N3}' -f $ItemStopwatch.Elapsed.TotalSeconds
            $Timings.Add("$CacheType : ${ElapsedSeconds}s")
            Write-Information "  [$CollectionType] Completed $CacheType for $TenantFilter - Took ${ElapsedSeconds} seconds"
            $SuccessCount++
        } catch {
            $ItemStopwatch.Stop()
            $ElapsedSeconds = '{0:N3}' -f $ItemStopwatch.Elapsed.TotalSeconds
            $FailedCount++
            $Errors.Add("$CacheType : $($_.Exception.Message)")
            $Timings.Add("$CacheType : ${ElapsedSeconds}s (FAILED)")
            Write-Warning "  [$CollectionType] Failed $CacheType for $TenantFilter after ${ElapsedSeconds} seconds: $($_.Exception.Message)"
        }
    }

    $CollectionStopwatch.Stop()
    $TotalElapsed = '{0:N3}' -f $CollectionStopwatch.Elapsed.TotalSeconds
    $Summary = "$CollectionType collection for $TenantFilter completed in ${TotalElapsed} seconds - $SuccessCount succeeded, $FailedCount failed out of $($CacheTypes.Count)"
    Write-Information $Summary
    Write-Information "  Timings: $($Timings -join ' | ')"

    if ($FailedCount -gt 0) {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "$Summary. Errors: $($Errors -join '; ')" -sev Warning
    }

    return @{
        CollectionType = $CollectionType
        TenantFilter   = $TenantFilter
        Success        = $SuccessCount
        Failed         = $FailedCount
        Total          = $CacheTypes.Count
        TotalSeconds   = $TotalElapsed
        Timings        = @($Timings)
        Errors         = @($Errors)
    }
}
