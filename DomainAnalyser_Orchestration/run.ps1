param($Context)

try { 

  $DurableRetryOptions = @{
    FirstRetryInterval  = (New-TimeSpan -Seconds 5)
    MaxNumberOfAttempts = 3
    BackoffCoefficient  = 2
  }
  $RetryOptions = New-DurableRetryOptions @DurableRetryOptions

  # Sync tenants
  try {
    Invoke-ActivityFunction -FunctionName 'DomainAnalyser_GetTenantDomains' -Input 'Tenants'
  }
  catch { Write-Host "EXCEPTION: TenantDomains $($_.Exception.Message)" }

  # Get list of all domains to process
  $Batch = Invoke-ActivityFunction -FunctionName 'Activity_GetAllTableRows' -Input 'Domains'
 
  $ParallelTasks = foreach ($Item in $Batch) {
    Invoke-DurableActivity -FunctionName 'DomainAnalyser_All' -Input $item -NoWait -RetryOptions $RetryOptions
  }
  
  # Collect activity function results and send to database
  $TableParams = Get-CippTable -tablename 'Domains'
  $TableParams.Entity = Wait-ActivityFunction -Task $ParallelTasks
  $TableParams.Force = $true
  $TableParams = $TableParams | ConvertTo-Json -Compress

  try {
    Invoke-ActivityFunction -FunctionName 'Activity_AddOrUpdateTableRows' -Input $TableParams
  }
  catch {
    Write-Host "Orchestrator exception UpdateDomains $($_.Exception.Message)"
  }
}
catch {
  Write-LogMessage -API 'DomainAnalyser' -message "Domain Analyser Orchestrator Error $($_.Exception.Message)" -sev info
  #Write-Host $_.Exception | ConvertTo-Json
}
finally {
  Write-LogMessage -API 'DomainAnalyser' -message 'Domain Analyser has Finished' -sev Info
}