function Push-CIPPTestsRun {
    <#
    .SYNOPSIS
        PostExecution function to run tests after data collection completes
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    try {
        $TenantFilter = $Item.Parameters.TenantFilter
        Write-Information "PostExecution: Starting tests for tenant: $TenantFilter after data collection completed"
        Write-LogMessage -API 'Tests' -tenant $TenantFilter -message 'Starting test run after data collection' -sev Info

        # Call the test run function
        $Result = Invoke-CIPPTestsRun -TenantFilter $TenantFilter

        Write-LogMessage -API 'Tests' -tenant $TenantFilter -message "Test run started. Instance ID: $($Result.InstanceId)" -sev Info
        Write-Information "PostExecution: Tests started with Instance ID: $($Result.InstanceId)"

        return @{
            Success    = $true
            InstanceId = $Result.InstanceId
            Message    = $Result.Message
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $TenantFilter -message "Failed to start test run: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Write-Warning "PostExecution: Error starting tests - $($ErrorMessage.NormalizedError)"

        return @{
            Success = $false
            Error   = $ErrorMessage.NormalizedError
        }
    }
}
