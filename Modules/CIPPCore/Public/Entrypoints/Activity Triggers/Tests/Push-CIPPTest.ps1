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
        $FunctionName = "Invoke-CippTest$TestId"

        if (-not (Get-Command $FunctionName -ErrorAction SilentlyContinue)) {
            Write-LogMessage -API 'Tests' -tenant $TenantFilter -message "Test function not found: $FunctionName" -sev Error
            return
        }

        Write-Information "Executing $FunctionName for $TenantFilter"
        & $FunctionName -Tenant $TenantFilter
        Write-Host "Returning true, test has run for $tenantFilter"
        return @{ testRun = $true }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $TenantFilter -message "Failed to run test $TestId $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
