function Invoke-ExecStandardTemplateSchedule {
  <#
  .FUNCTIONALITY
      Entrypoint
  .ROLE
      Tenant.Standards.ReadWrite
  #>
  [CmdletBinding()]
  param($Request, $TriggerMetadata)

  $APIName = $Request.Params.CIPPEndpoint
  $Headers = $Request.Headers
  $ID = $Request.Body.TemplateId ?? $Request.Query.TemplateId
  # The stored field is runManually: $true means "do not run on schedule".
  $RunManually = $Request.Body.runManually -eq $true -or $Request.Body.runManually -eq 'true'
  $StatusCode = [HttpStatusCode]::InternalServerError

  try {
    $Table = Get-CippTable -tablename 'templates'
    $SafeID = ConvertTo-CIPPODataFilterValue -Value $ID -Type Guid
    $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'StandardsTemplateV2' and RowKey eq '$SafeID'"
    if (-not $Entity) {
      $StatusCode = [HttpStatusCode]::BadRequest
      throw "Standards template '$ID' was not found."
    }

    $Data = $Entity.JSON | ConvertFrom-Json -Depth 100
    if ($Data.type -eq 'drift') {
      $StatusCode = [HttpStatusCode]::BadRequest
      throw "Template '$($Data.templateName)' is a drift template and does not run on a schedule."
    }

    $Data | Add-Member -NotePropertyName 'runManually' -NotePropertyValue $RunManually -Force
    $Data | Add-Member -NotePropertyName 'updatedBy' -NotePropertyValue ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails -Force
    $Data | Add-Member -NotePropertyName 'updatedAt' -NotePropertyValue (Get-Date).ToUniversalTime() -Force

    $Entity.JSON = (ConvertTo-Json -Compress -Depth 100 -InputObject $Data)
    $null = Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force

    $Result = $RunManually ?
        "Disabled the schedule for template '$($Data.templateName)'. It will only run when triggered manually." :
        "Enabled the schedule for template '$($Data.templateName)'."
    Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev Info
    $StatusCode = [HttpStatusCode]::OK
  } catch {
    if ($StatusCode -eq [HttpStatusCode]::BadRequest) {
      $Result = $_.Exception.Message
      Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev Warning
    } else {
      $ErrorMessage = Get-CippException -Exception $_
      $Result = "Failed to update the schedule for template id $($ID). Error: $($ErrorMessage.NormalizedError)"
      Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev Error -LogData $ErrorMessage
    }
  }

  return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = @{ 'Results' = $Result } })
}