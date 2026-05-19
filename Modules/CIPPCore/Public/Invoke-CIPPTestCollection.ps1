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
        $CustomFunction = Get-Command -Name 'Invoke-CippTestCustomScripts' -ErrorAction SilentlyContinue
        if (-not $CustomFunction) {
            Write-Information 'Invoke-CippTestCustomScripts not found — skipping Custom suite'
            return @{ SuiteName = $SuiteName; TenantFilter = $TenantFilter; Success = 0; Failed = 0; Total = 0; TotalSeconds = 0; Timings = @(); Errors = @() }
        }

        $Table = Get-CippTable -TableName 'CustomPowershellScripts'
        $AllScripts = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CustomScript'")

        # Get the latest version of each script guid, filter to enabled only
        $EnabledGuids = $AllScripts | Group-Object -Property ScriptGuid | ForEach-Object {
            $_.Group | Sort-Object -Property Version -Descending | Select-Object -First 1
        } | Where-Object {
            -not $_.PSObject.Properties['Enabled'] -or [bool]$_.Enabled
        } | Select-Object -ExpandProperty ScriptGuid

        if ($EnabledGuids.Count -eq 0) {
            Write-Information 'No enabled custom scripts found — skipping Custom suite'
            return @{ SuiteName = $SuiteName; TenantFilter = $TenantFilter; Success = 0; Failed = 0; Total = 0; TotalSeconds = 0; Timings = @(); Errors = @() }
        }

        Write-Information "Starting Custom suite for $TenantFilter ($($EnabledGuids.Count) scripts)"

        $Table = Get-CippTable -tablename 'CippTestResults'
        $ResultBatch = [System.Collections.Generic.List[hashtable]]::new()

        foreach ($Guid in $EnabledGuids) {
            $ItemStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                Write-Information "  [Custom] Running CustomScript-$Guid for $TenantFilter"
                $TestOutput = @(Invoke-CippTestCustomScripts -Tenant $TenantFilter -ScriptGuid $Guid)
                foreach ($Entity in $TestOutput) {
                    if ($Entity -is [hashtable] -and $Entity.PartitionKey -and $Entity.RowKey) {
                        $ResultBatch.Add($Entity)
                    }
                }
                if ($ResultBatch.Count -ge 100) {
                    Add-CIPPAzDataTableEntity @Table -Entity @($ResultBatch) -Force
                    Write-Information "  [Custom] Flushed $($ResultBatch.Count) results to table"
                    $ResultBatch.Clear()
                }
                $ItemStopwatch.Stop()
                $ElapsedSeconds = [math]::Round($ItemStopwatch.Elapsed.TotalSeconds, 3)
                $Timings.Add("CustomScript-$Guid : ${ElapsedSeconds}s")
                Write-Information "  [Custom] Completed CustomScript-$Guid - ${ElapsedSeconds}s"
                $SuccessCount++
            } catch {
                $ItemStopwatch.Stop()
                $ElapsedSeconds = [math]::Round($ItemStopwatch.Elapsed.TotalSeconds, 3)
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

        $SuiteStopwatch.Stop()
        $TotalElapsed = [math]::Round($SuiteStopwatch.Elapsed.TotalSeconds, 3)
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

    # Standard suites: discover functions by name pattern via Get-Command
    $Pattern = $SuitePatterns[$SuiteName]
    $TestFunctions = @(Get-Command -Name $Pattern -ErrorAction SilentlyContinue)
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
            Write-Information "  [$SuiteName] Running $($TestFunction.Name) for $TenantFilter"
            $TestOutput = @(& $TestFunction.Name -Tenant $TenantFilter)
            foreach ($Entity in $TestOutput) {
                if ($Entity -is [hashtable] -and $Entity.PartitionKey -and $Entity.RowKey) {
                    $ResultBatch.Add($Entity)
                }
            }
            if ($ResultBatch.Count -ge 100) {
                Add-CIPPAzDataTableEntity @Table -Entity @($ResultBatch) -Force
                Write-Information "  [$SuiteName] Flushed $($ResultBatch.Count) results to table"
                $ResultBatch.Clear()
            }
            $ItemStopwatch.Stop()
            $ElapsedSeconds = [math]::Round($ItemStopwatch.Elapsed.TotalSeconds, 3)
            $Timings.Add("$($TestFunction.Name) : ${ElapsedSeconds}s")
            Write-Information "  [$SuiteName] Completed $($TestFunction.Name) - ${ElapsedSeconds}s"
            $SuccessCount++
        } catch {
            $ItemStopwatch.Stop()
            $ElapsedSeconds = [math]::Round($ItemStopwatch.Elapsed.TotalSeconds, 3)
            $FailedCount++
            $Errors.Add("$($TestFunction.Name) : $($_.Exception.Message)")
            $Timings.Add("$($TestFunction.Name) : ${ElapsedSeconds}s (FAILED)")
            Write-Warning "  [$SuiteName] Failed $($TestFunction.Name) after ${ElapsedSeconds}s: $($_.Exception.Message)"
        }
    }

    # Final flush
    if ($ResultBatch.Count -gt 0) {
        Add-CIPPAzDataTableEntity @Table -Entity @($ResultBatch) -Force
        Write-Information "  [$SuiteName] Flushed final $($ResultBatch.Count) results to table"
    }

    $SuiteStopwatch.Stop()
    $TotalElapsed = [math]::Round($SuiteStopwatch.Elapsed.TotalSeconds, 3)
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
