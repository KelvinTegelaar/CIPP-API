param($Context)

try {

    $DurableRetryOptions = @{
        FirstRetryInterval  = (New-TimeSpan -Seconds 5)
        MaxNumberOfAttempts = 1
        BackoffCoefficient  = 2
    }
    $RetryOptions = New-DurableRetryOptions @DurableRetryOptions

    # Sync tenants
    $GotDomains = $false
    try {
        $GotDomains = Invoke-ActivityFunction -FunctionName 'DomainAnalyser_GetTenantDomains' -Input 'Tenants'
    } catch { Write-Host "EXCEPTION: TenantDomains $($_.Exception.Message)" }

    if ($GotDomains) {
        # Get list of all domains to process
        $Batch = Invoke-ActivityFunction -FunctionName 'Activity_GetAllTableRows' -Input 'Domains'

        if (($Batch | Measure-Object).Count -gt 0) {
            $ParallelTasks = foreach ($Item in $Batch) {
                Invoke-DurableActivity -FunctionName 'DomainAnalyser_All' -Input $item -NoWait -RetryOptions $RetryOptions
            }
            $null = Wait-ActivityFunction -Task $ParallelTasks
        }
    }
} catch {
    Write-LogMessage -API 'DomainAnalyser' -message 'Domain Analyser Orchestrator Error' -sev info -LogData (Get-CippException -Exception $_)
    #Write-Host $_.Exception | ConvertTo-Json
} finally {
    Write-LogMessage -API 'DomainAnalyser' -message 'Domain Analyser has Finished' -sev Info
}