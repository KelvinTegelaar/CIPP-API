param($Context)

try { 
  New-Item 'Cache_DomainAnalyser' -ItemType Directory -ErrorAction SilentlyContinue
  New-Item 'Cache_DomainAnalyser\CurrentlyRunning.txt' -ItemType File -Force

  $DomainTable = Get-CippTable -Table Domains

  $TenantDomains = Invoke-ActivityFunction -FunctionName 'DomainAnalyser_GetTenantDomains' -Input 'Tenants'

  # Process tenant domain results
  foreach ($Tenant in $TenantDomains) {
    $TenantDetails = $Tenant | ConvertTo-Json

    $ExistingDomain = @{
      Table        = $DomainTable
      rowKey       = $Tenant.Domain
      partitionKey = $Tenant.Tenant
    }
    $Domain = Get-AzTableRow @ExistingDomain

    if (!$Domain) {
      $DomainObject = @{
        Table        = $DomainTable
        rowKey       = $Tenant.Domain
        partitionKey = $Tenant.Tenant
        property     = @{
          DomainAnalyser = ''
          TenantDetails  = $TenantDetails
          DkimSelectors  = ''
          MailProviders  = ''
        }
      }
      Add-AzTableRow @DomainObject | Out-Null
    }
    else {
      $Domain.TenantDetails = $TenantDetails
      $Domain | Update-AzTableRow -Table $DomainTable | Out-Null
    }
  }

  # Get list of all domains to process
  $DomainParam = @{
    Table = $DomainTable
  }
  
  $Batch = Get-AzTableRow @DomainParam

  $ParallelTasks = foreach ($Item in $Batch) {
    Invoke-DurableActivity -FunctionName 'DomainAnalyser_All' -Input $item -NoWait
  }

  $Outputs = Wait-ActivityFunction -Task $ParallelTasks
  Log-request -API 'DomainAnalyser' -message "Outputs found count = $($Outputs.count)" -sev Info

  foreach ($DomainObject in $Outputs) {
    [PSCustomObject]$DomainObject | Update-AzTableRow @DomainParam | Out-Null
  }
}
catch {
  Log-request -API 'DomainAnalyser' -message "Domain Analyser Orchestrator Error $($_.Exception.Message)" -sev info
  Write-Host $_.Exception | ConvertTo-Json
}
finally {
  Log-request -API 'DomainAnalyser' -message 'Domain Analyser has Finished' -sev Info
  Remove-Item 'Cache_DomainAnalyser\CurrentlyRunning.txt' -Force
}