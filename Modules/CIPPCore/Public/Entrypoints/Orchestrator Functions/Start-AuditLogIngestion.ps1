function Start-AuditLogIngestion {
    <#
  .SYNOPSIS
  Start the Audit Log Ingestion Orchestrator using Office 365 Management Activity API

  .DESCRIPTION
  Orchestrator that creates batches of tenants to ingest audit logs from the Office 365 Management Activity API.
  Each tenant is processed by Push-AuditLogIngestion activity function.

  .FUNCTIONALITY
  Entrypoint
  #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    try {
        Write-Information 'Office 365 Management Activity API: Starting audit log ingestion orchestrator'
        # Get webhook rules to determine which tenants to monitor
        $WebhookRulesTable = Get-CippTable -TableName 'WebhookRules'
        $WebhookRules = Get-CIPPAzDataTableEntity @WebhookRulesTable -Filter "PartitionKey eq 'Webhookv2'"
        if (($WebhookRules | Measure-Object).Count -eq 0) {
            Write-Information 'No webhook rules defined, skipping audit log ingestion'
            return
        }

        # Process webhook rules to get tenant list
        $ConfigEntries = $WebhookRules | ForEach-Object {
            $ConfigEntry = $_
            if (!$ConfigEntry.excludedTenants) {
                $ConfigEntry | Add-Member -MemberType NoteProperty -Name 'excludedTenants' -Value @() -Force
            } else {
                $ConfigEntry.excludedTenants = $ConfigEntry.excludedTenants | ConvertFrom-Json
            }
            $ConfigEntry.Tenants = $ConfigEntry.Tenants | ConvertFrom-Json
            $ConfigEntry
        }

    $TenantList = Get-Tenants -IncludeErrors
    $TenantsToProcess = [System.Collections.Generic.List[object]]::new()

    foreach ($Tenant in $TenantList) {
      # Check if tenant has any webhook rules and collect content types
      $TenantInConfig = $false
      $MatchingConfigs = [System.Collections.Generic.List[object]]::new()

      foreach ($ConfigEntry in $ConfigEntries) {
        if ($ConfigEntry.excludedTenants.value -contains $Tenant.defaultDomainName) {
          continue
        }
        $TenantsList = Expand-CIPPTenantGroups -TenantFilter ($ConfigEntry.Tenants)
        if ($TenantsList.value -contains $Tenant.defaultDomainName -or $TenantsList.value -contains 'AllTenants') {
          $TenantInConfig = $true
          $MatchingConfigs.Add($ConfigEntry)
        }
      }

      if ($TenantInConfig -and $MatchingConfigs.Count -gt 0) {
        # Extract unique content types from webhook rules (e.g., Audit.Exchange, Audit.SharePoint)
        $ContentTypes = @($MatchingConfigs | Select-Object -Property type | Where-Object { $_.type } | Sort-Object -Property type -Unique | ForEach-Object { $_.type })

        if ($ContentTypes.Count -gt 0) {
          $TenantsToProcess.Add([PSCustomObject]@{
            defaultDomainName = $Tenant.defaultDomainName
            customerId = $Tenant.customerId
            ContentTypes = $ContentTypes
          })
        }
      }
    }        if ($TenantsToProcess.Count -eq 0) {
            Write-Information 'No tenants configured for audit log ingestion'
            return
        }

        Write-Information "Audit Log Ingestion: Processing $($TenantsToProcess.Count) tenants"

        if ($PSCmdlet.ShouldProcess('Start-AuditLogIngestion', 'Starting Audit Log Ingestion')) {
      $Queue = New-CippQueueEntry -Name 'Audit Logs Ingestion' -Reference 'AuditLogsIngestion' -TotalTasks $TenantsToProcess.Count
      $Batch = $TenantsToProcess | Select-Object @{Name = 'TenantFilter'; Expression = { $_.defaultDomainName } }, @{Name = 'TenantId'; Expression = { $_.customerId } }, @{Name = 'ContentTypes'; Expression = { $_.ContentTypes } }, @{Name = 'QueueId'; Expression = { $Queue.RowKey } }, @{Name = 'FunctionName'; Expression = { 'AuditLogIngestion' } }
      $InputObject = [PSCustomObject]@{
                OrchestratorName = 'AuditLogsIngestion'
                Batch            = @($Batch)
                SkipLog          = $true
            }
            Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
            Write-Information "Started audit log ingestion orchestration for $($TenantsToProcess.Count) tenants"
        }
    } catch {
        Write-LogMessage -API 'AuditLogIngestion' -message 'Error in audit log ingestion orchestrator' -sev Error -LogData (Get-CippException -Exception $_)
        Write-Information "Audit log ingestion orchestrator error: $($_.Exception.Message)"
    }
}
