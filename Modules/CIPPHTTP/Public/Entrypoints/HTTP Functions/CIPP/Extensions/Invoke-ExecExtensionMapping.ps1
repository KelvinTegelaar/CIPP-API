Function Invoke-ExecExtensionMapping {
  <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Extension.ReadWrite
    #>
  [CmdletBinding()]
  param($Request, $TriggerMetadata)

  $APIName = $Request.Params.CIPPEndpoint
  $Headers = $Request.Headers


  $Table = Get-CIPPTable -TableName CippMapping

  if ($Request.Query.List) {
    switch ($Request.Query.List) {
      'HaloPSA' {
        $Result = Get-HaloMapping -CIPPMapping $Table
      }
      'NinjaOne' {
        $Result = Get-NinjaOneOrgMapping -CIPPMapping $Table
      }
      'NinjaOneFields' {
        $Result = Get-NinjaOneFieldMapping -CIPPMapping $Table
      }
      'Hudu' {
        $Result = Get-HuduMapping -CIPPMapping $Table
      }
      'HuduFields' {
        $Result = Get-HuduFieldMapping -CIPPMapping $Table
      }
      'Sherweb' {
        $Result = Get-SherwebMapping -CIPPMapping $Table
      }
      'HaloPSAFields' {
        # Outcomes and priorities are scoped to a ticket type. The settings page sends the
        # ticket type currently selected in the form so the lists follow the dropdown; without
        # it both fall back to whatever ticket type was last saved.
        $SelectedTicketType = $Request.Query.TicketType
        $TicketTypes = Get-HaloTicketType
        $Outcomes = Get-HaloTicketOutcome -TicketType $SelectedTicketType
        $Priorities = Get-HaloPriority -TicketType $SelectedTicketType
        $Result = @{
          'TicketTypes' = $TicketTypes
          'Outcomes'    = $Outcomes
          'Priorities'  = $Priorities
        }
      }
      'PWPushFields' {
        $Accounts = Get-PwPushAccount
        $Result = @{
          'Accounts' = $Accounts
        }
      }
    }
  }

  # AnyTenant: mapping writes wipe and rewrite whole partitions and re-register per-tenant
  # sync tasks, so they require an unrestricted tenant scope
  if ($Request.Query.AddMapping -or $Request.Query.AutoMapping) {
    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    if ($AllowedTenants -notcontains 'AllTenants') {
      return ([HttpResponseContext]@{
          StatusCode = [HttpStatusCode]::Forbidden
          Body       = 'Editing extension mappings requires unrestricted tenant access'
        })
    }
  }

  try {
    if ($Request.Query.AddMapping) {
      switch ($Request.Query.AddMapping) {
        'Sherweb' {
          $Result = Set-SherwebMapping -CIPPMapping $Table -APIName $APIName -Request $Request
        }
        'HaloPSA' {
          $Result = Set-HaloMapping -CIPPMapping $Table -APIName $APIName -Request $Request
        }
        'NinjaOne' {
          $Result = Set-NinjaOneOrgMapping -CIPPMapping $Table -APIName $APIName -Request $Request
          Register-CIPPExtensionScheduledTasks
        }
        'NinjaOneFields' {
          $Result = Set-NinjaOneFieldMapping -CIPPMapping $Table -APIName $APIName -Request $Request -TriggerMetadata $TriggerMetadata
          Register-CIPPExtensionScheduledTasks
        }
        'Hudu' {
          $Result = Set-HuduMapping -CIPPMapping $Table -APIName $APIName -Request $Request
          Register-CIPPExtensionScheduledTasks
        }
        'HuduFields' {
          $Result = Set-ExtensionFieldMapping -CIPPMapping $Table -APIName $APIName -Request $Request -Extension 'Hudu'
          Register-CIPPExtensionScheduledTasks
        }
      }
    }
    $StatusCode = [HttpStatusCode]::OK
  }
  catch {
    $ErrorMessage = Get-CippException -Exception $_
    $Result = "Mapping API failed. $($ErrorMessage.NormalizedError)"
    Write-LogMessage -API $APIName -headers $Headers -message $Result -Sev 'Error' -LogData $ErrorMessage
    $StatusCode = [HttpStatusCode]::InternalServerError
  }

  try {
    if ($Request.Query.AutoMapping) {
      switch ($Request.Query.AutoMapping) {
        'NinjaOne' {
          $Batch = [PSCustomObject]@{
            'NinjaAction'  = 'StartAutoMapping'
            'FunctionName' = 'NinjaOneQueue'
          }
          $InputObject = [PSCustomObject]@{
            OrchestratorName = 'NinjaOneOrchestrator'
            Batch            = @($Batch)
          }
          #Write-Host ($InputObject | ConvertTo-Json)
          $InstanceId = Start-CIPPOrchestrator -InputObject $InputObject
          Write-Host "Started permissions orchestration with ID = '$InstanceId'"
          $Result = 'AutoMapping Request has been queued. Exact name matches will appear first and matches on device names and serials will take longer. Please check the CIPP Logbook and refresh the page once complete.'
        }
        'HaloPSA' {
          $Result = Invoke-HaloAutoMap -CIPPMapping $Table
        }
      }
    }
    $StatusCode = [HttpStatusCode]::OK
  }
  catch {
    $ErrorMessage = Get-CippException -Exception $_
    $Result = "Mapping API failed. $($ErrorMessage.NormalizedError)"
    Write-LogMessage -API $APIName -headers $Headers -message $Result -Sev 'Error' -LogData $ErrorMessage
    $StatusCode = [HttpStatusCode]::InternalServerError
  }

  return ([HttpResponseContext]@{
      StatusCode = $StatusCode
      Body       = $Result
    })

}
