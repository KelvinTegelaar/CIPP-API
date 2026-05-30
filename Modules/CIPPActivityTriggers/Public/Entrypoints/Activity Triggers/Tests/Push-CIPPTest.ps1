function Push-CIPPTest {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param(
        $Item
    )

    $TenantFilter = $Item.TenantFilter
    $TestId = $Item.TestId

    Write-Information "Running test $TestId for tenant $TenantFilter"

    # Per-process cache of resolved test function commands so that a flat orchestrator
    # firing thousands of activities doesn't repeat the module command-table walk
    # for every task.
    if (-not $script:CIPPTestFunctionLookup) {
        $script:CIPPTestFunctionLookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        Write-Information "[CacheInit] CIPPTestFunctionLookup initialized in PID $PID"
    }

    try {
        if ($TestId -like 'CustomScript-*') {
            $ScriptGuid = $TestId -replace '^CustomScript-', ''
            Write-Information "Executing Invoke-CippTestCustomScripts for $TenantFilter (ScriptGuid: $ScriptGuid)"
            Invoke-CippTestCustomScripts -Tenant $TenantFilter -ScriptGuid $ScriptGuid
            Write-Host "Returning true, test has run for $tenantFilter"
            return @{ testRun = $true }
        }

        $FunctionName = "Invoke-CippTest$TestId"

        if ($script:CIPPTestFunctionLookup.ContainsKey($FunctionName)) {
            Write-Information "[CacheHit] CIPPTestFunctionLookup PID=$PID Key=$FunctionName Size=$($script:CIPPTestFunctionLookup.Count)"
        } else {
            Write-Information "[CacheMiss] CIPPTestFunctionLookup PID=$PID Key=$FunctionName Size=$($script:CIPPTestFunctionLookup.Count) - resolving via Get-Command"
            $script:CIPPTestFunctionLookup[$FunctionName] = Get-Command $FunctionName -Module CIPPTests -ErrorAction SilentlyContinue
        }
        $TestCommand = $script:CIPPTestFunctionLookup[$FunctionName]
        if (-not $TestCommand) {
            Write-LogMessage -API 'Tests' -tenant $TenantFilter -message "Test function not found: $FunctionName" -sev Error
            return @{ testRun = $false }
        }

        Write-Information "Executing $FunctionName for $TenantFilter"
        & $TestCommand -Tenant $TenantFilter
        Write-Host "Returning true, test has run for $tenantFilter"
        return @{ testRun = $true }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $TenantFilter -message "Failed to run test $TestId $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return @{ testRun = $false }
    }
}
