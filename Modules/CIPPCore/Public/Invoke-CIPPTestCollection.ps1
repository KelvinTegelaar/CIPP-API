function Invoke-CIPPTestCollection {
    <#
    .SYNOPSIS
        Execute all tests for a named test suite against a tenant

    .DESCRIPTION
        Runs all Invoke-CippTest* functions belonging to a suite sequentially within a
        single activity invocation. Suite membership is determined entirely by function
        name prefix via Get-Command — no filesystem paths are used, so this works
        correctly with ModuleBuilder compiled modules.

        Suite-to-pattern map (single source of truth):
        - ZTNA             → Invoke-CippTestZTNA*
        - ORCA             → Invoke-CippTestORCA*
        - EIDSCA           → Invoke-CippTestEIDSCA*
        - CISA             → Invoke-CippTestCISA*
        - CIS              → Invoke-CippTestCIS_*
        - SMB1001          → Invoke-CippTestSMB1001_*
        - CopilotReadiness → Invoke-CippTestCopilotReady*
        - Custom           → Special: enumerates enabled ScriptGuids from DB and calls
                             Invoke-CippTestCustomScripts once per guid (the function
                             requires a ScriptGuid parameter to filter the table query)

    .PARAMETER SuiteName
        Name of the test suite to execute. Must match a key in the internal suite map.

    .PARAMETER TenantFilter
        Tenant domain to run tests against.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('ZTNA', 'ORCA', 'EIDSCA', 'CISA', 'CIS', 'SMB1001', 'CopilotReadiness', 'GenericTests', 'Custom')]
        [string]$SuiteName,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    # Canonical suite-to-pattern map — single source of truth for grouping.
    # Discovery is done via Get-Command so this is path-independent and ModuleBuilder safe.
    $SuitePatterns = @{
        ZTNA             = 'Invoke-CippTestZTNA*'
        ORCA             = 'Invoke-CippTestORCA*'
        EIDSCA           = 'Invoke-CippTestEIDSCA*'
        CISA             = 'Invoke-CippTestCISA*'
        CIS              = 'Invoke-CippTestCIS_*'
        SMB1001          = 'Invoke-CippTestSMB1001_*'
        CopilotReadiness = 'Invoke-CippTestCopilotReady*'
        GenericTests     = 'Invoke-CippTestGenericTest*'
    }

    $SuiteStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $SuccessCount = 0
    $FailedCount = 0
    $Errors = [System.Collections.Generic.List[string]]::new()
    $Timings = [System.Collections.Generic.List[string]]::new()

    # Custom suite: Invoke-CippTestCustomScripts now requires a ScriptGuid parameter.
    # Enumerate distinct enabled script guids from the DB and call once per guid.
    if ($SuiteName -eq 'Custom') {
        if (-not (Get-Command -Name 'Invoke-CippTestCustomScripts' -ErrorAction SilentlyContinue)) {
            Write-Information 'Invoke-CippTestCustomScripts not found — skipping Custom suite'
            return @{ SuiteName = $SuiteName; TenantFilter = $TenantFilter; Success = 0; Failed = 0; Total = 0; TotalSeconds = 0; Timings = @(); Errors = @() }
        }

        $Table = Get-CippTable -TableName 'CustomPowershellScripts'
        $AllScripts = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CustomScript'")

        # Single-pass "latest enabled version per ScriptGuid".
        # The previous Group-Object | ForEach-Object { Sort-Object | Select -First 1 }
        # pipeline allocated a Group container per guid and ran an O(n log n) sort per group;
        # this hashtable walk is O(n) total and avoids the pipeline overhead entirely.
        $LatestByGuid = @{}
        foreach ($Script in $AllScripts) {
            $Guid = $Script.ScriptGuid
            if (-not $Guid) { continue }
            $Existing = $LatestByGuid[$Guid]
            if (-not $Existing -or [int]$Script.Version -gt [int]$Existing.Version) {
                $LatestByGuid[$Guid] = $Script
            }
        }

        $EnabledGuidsList = [System.Collections.Generic.List[string]]::new()
        foreach ($Latest in $LatestByGuid.Values) {
            # Cache the property lookup — calling .PSObject.Properties[''] reflects through
            # the PSObject member set on every invocation in the original code.
            $EnabledProp = $Latest.PSObject.Properties['Enabled']
            if (-not $EnabledProp -or [bool]$EnabledProp.Value) {
                $EnabledGuidsList.Add($Latest.ScriptGuid)
            }
        }
        $EnabledGuids = $EnabledGuidsList.ToArray()

        if ($EnabledGuids.Count -eq 0) {
            Write-Information 'No enabled custom scripts found — skipping Custom suite'
            return @{ SuiteName = $SuiteName; TenantFilter = $TenantFilter; Success = 0; Failed = 0; Total = 0; TotalSeconds = 0; Timings = @(); Errors = @() }
        }

        Write-Information "Starting Custom suite for $TenantFilter ($($EnabledGuids.Count) scripts)"

        $Table = Get-CippTable -tablename 'CippTestResults'
        $ResultBatch = [System.Collections.Generic.List[hashtable]]::new()
        $AlertBatch = [System.Collections.Generic.List[object]]::new()

        foreach ($Guid in $EnabledGuids) {
            $ItemStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                Write-Information "  [Custom] Running CustomScript-$Guid for $TenantFilter"
                $TestOutput = @(Invoke-CippTestCustomScripts -Tenant $TenantFilter -ScriptGuid $Guid)
                foreach ($Entity in $TestOutput) {
                    if ($Entity -is [hashtable] -and $Entity.PartitionKey -and $Entity.RowKey) {
                        $ResultBatch.Add($Entity)
                    } elseif ($Entity -isnot [hashtable] -and $Entity.PSObject.Properties['CippCustomTestAlert']) {
                        $AlertBatch.Add($Entity)
                    }
                }
                if ($ResultBatch.Count -ge 100) {
                    Add-CIPPAzDataTableEntity @Table -Entity @($ResultBatch) -Force
                    Write-Information "  [Custom] Flushed $($ResultBatch.Count) results to table"
                    $ResultBatch.Clear()
                }
                $ItemStopwatch.Stop()
                $ElapsedSeconds = '{0:N3}' -f $ItemStopwatch.Elapsed.TotalSeconds
                $Timings.Add("CustomScript-$Guid : ${ElapsedSeconds}s")
                Write-Information "  [Custom] Completed CustomScript-$Guid - ${ElapsedSeconds}s"
                $SuccessCount++
            } catch {
                $ItemStopwatch.Stop()
                $ElapsedSeconds = '{0:N3}' -f $ItemStopwatch.Elapsed.TotalSeconds
                $FailedCount++
                $Errors.Add("CustomScript-$Guid : $($_.Exception.Message)")
                $Timings.Add("CustomScript-$Guid : ${ElapsedSeconds}s (FAILED)")
                Write-Warning "  [Custom] Failed CustomScript-$Guid after ${ElapsedSeconds}s: $($_.Exception.Message)"
            }
        }

        # Final flush
        if ($ResultBatch.Count -gt 0) {
            Add-CIPPAzDataTableEntity @Table -Entity @($ResultBatch) -Force
            Write-Information "  [Custom] Flushed final $($ResultBatch.Count) results to table"
        }

        # Ship a single aggregated alert for the tenant covering all alert-worthy results.
        if ($AlertBatch.Count -gt 0) {
            Write-Information "  [Custom] Shipping $($AlertBatch.Count) custom test alert(s) for $TenantFilter"
            Send-CIPPCustomTestAlert -TenantFilter $TenantFilter -Alerts @($AlertBatch)
        }

        $SuiteStopwatch.Stop()
        $TotalElapsed = '{0:N3}' -f $SuiteStopwatch.Elapsed.TotalSeconds
        $Summary = "Custom suite for $TenantFilter completed in ${TotalElapsed}s — $SuccessCount/$($EnabledGuids.Count) ran, $FailedCount errored"
        Write-Information $Summary
        Write-Information "  Timings: $($Timings -join ' | ')"
        if ($FailedCount -gt 0) {
            Write-LogMessage -API 'Tests' -tenant $TenantFilter -message "$Summary. Errors: $($Errors -join '; ')" -sev Warning
        }
        return @{
            SuiteName    = $SuiteName
            TenantFilter = $TenantFilter
            Success      = $SuccessCount
            Failed       = $FailedCount
            Total        = $EnabledGuids.Count
            TotalSeconds = $TotalElapsed
            Timings      = @($Timings)
            Errors       = @($Errors)
        }
    }

    # Standard suites: discover functions by name pattern via Get-Command.
    $Pattern = $SuitePatterns[$SuiteName]
    $TestFunctions = @(Get-Command -Name $Pattern -Module CIPPTests -ErrorAction SilentlyContinue)
    if ($TestFunctions.Count -eq 0) {
        Write-Information "No test functions found for suite $SuiteName (pattern: $Pattern) — skipping"
        return @{
            SuiteName    = $SuiteName
            TenantFilter = $TenantFilter
            Success      = 0
            Failed       = 0
            Total        = 0
            TotalSeconds = 0
            Timings      = @()
            Errors       = @()
        }
    }

    Write-Information "Starting $SuiteName suite for $TenantFilter ($($TestFunctions.Count) tests)"

    $Table = Get-CippTable -tablename 'CippTestResults'
    $ResultBatch = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($TestFunction in $TestFunctions) {
        $ItemStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $TestOutput = @(& $TestFunction -Tenant $TenantFilter)
            foreach ($Entity in $TestOutput) {
                if ($Entity -is [hashtable] -and $Entity.PartitionKey) {
                    $ResultBatch.Add($Entity)
                }
            }
            if ($ResultBatch.Count -ge 100) {
                Add-CIPPAzDataTableEntity @Table -Entity @($ResultBatch) -Force
                $ResultBatch.Clear()
            }
            $ItemStopwatch.Stop()
            $Timings.Add(('{0} : {1:N3}s' -f $TestFunction.Name, $ItemStopwatch.Elapsed.TotalSeconds))
            $SuccessCount++
        } catch {
            $ItemStopwatch.Stop()
            $FailedCount++
            $Errors.Add("$($TestFunction.Name) : $($_.Exception.Message)")
            $Timings.Add(('{0} : {1:N3}s (FAILED)' -f $TestFunction.Name, $ItemStopwatch.Elapsed.TotalSeconds))
        }
    }

    # Final flush
    if ($ResultBatch.Count -gt 0) {
        Add-CIPPAzDataTableEntity @Table -Entity @($ResultBatch) -Force
        Write-Information "  [$SuiteName] Flushed final $($ResultBatch.Count) results to table"
    }

    $SuiteStopwatch.Stop()
    $TotalElapsed = '{0:N3}' -f $SuiteStopwatch.Elapsed.TotalSeconds
    $TestCount = $TestFunctions.Count
    $Summary = "$SuiteName suite for $TenantFilter completed in ${TotalElapsed}s — $SuccessCount/$TestCount ran, $FailedCount errored"
    Write-Information $Summary
    Write-Information "  Timings: $($Timings -join ' | ')"

    if ($FailedCount -gt 0) {
        Write-LogMessage -API 'Tests' -tenant $TenantFilter -message "$Summary. Errors: $($Errors -join '; ')" -sev Warning
    }

    return @{
        SuiteName    = $SuiteName
        TenantFilter = $TenantFilter
        Success      = $SuccessCount
        Failed       = $FailedCount
        Total        = $TestFunctions.Count
        TotalSeconds = $TotalElapsed
        Timings      = @($Timings)
        Errors       = @($Errors)
    }
}
