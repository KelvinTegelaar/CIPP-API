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

    try {
        if ($TestId -like 'CustomScript-*') {
            $ScriptGuid = $TestId -replace '^CustomScript-', ''
            Write-Information "Executing Invoke-CippTestCustomScripts for $TenantFilter (ScriptGuid: $ScriptGuid)"
            Invoke-CippTestCustomScripts -Tenant $TenantFilter -ScriptGuid $ScriptGuid
            Write-Host "Returning true, test has run for $tenantFilter"
            return @{ testRun = $true }
        }

        $FunctionName = "Invoke-CippTest$TestId"
        $TestCommand = Get-Command -Name $FunctionName -Module CIPPTests -ErrorAction SilentlyContinue
        if (-not $TestCommand) { throw "Test function not found: $FunctionName" }

        Write-Information "Executing $FunctionName for $TenantFilter"
        $TestResult = & $TestCommand -Tenant $TenantFilter
        $Table = Get-CippTable -tablename 'CippTestResults'
        Add-CIPPAzDataTableEntity @Table -Entity $TestResult -Force
        return @{ testRun = $true }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $TenantFilter -message "Failed to run test $TestId $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        # Rethrow so the queue counts the task as failed.
        throw
    }
}
