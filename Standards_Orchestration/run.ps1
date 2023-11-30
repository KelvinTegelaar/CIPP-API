param($Context)

$DurableRetryOptions = @{
    FirstRetryInterval  = (New-TimeSpan -Seconds 5)
    MaxNumberOfAttempts = 3
    BackoffCoefficient  = 2
}
$RetryOptions = New-DurableRetryOptions @DurableRetryOptions

$Batch = Invoke-ActivityFunction -FunctionName 'Standards_GetQueue' -Input 'LetsGo' -ErrorAction Stop
if ($null -ne $Batch -and ($Batch | Measure-Object).Count -gt 0) {
    $ParallelTasks = foreach ($Item in $Batch) {
        if ($item['Standard']) {
            try {
                Invoke-DurableActivity -FunctionName "Standards_$($item['Standard'])" -Input "$($item['Tenant'])" -NoWait -RetryOptions $RetryOptions -ErrorAction Stop
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Task error: $($_.Exception.Message)" -sev Error
            }
        }
    }

    if (($ParallelTasks | Measure-Object).Count -gt 0) {
        try {
            $Outputs = Wait-ActivityFunction -Task $ParallelTasks -ErrorAction Stop
        } catch {
            Write-Information "Standards Wait-ActivityFunction error: $($_.Exception.Message)"
        }
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'Deployment finished.' -sev Info
    }
} else {
    Write-Information 'No Standards to process'
}
