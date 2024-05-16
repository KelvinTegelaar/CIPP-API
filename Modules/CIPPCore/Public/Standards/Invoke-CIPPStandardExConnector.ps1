function Invoke-CIPPStandardExConnector {
  <#
    .FUNCTIONALITY
    Internal
    #>
  param($Tenant, $Settings)
  If ($Settings.remediate -eq $true) {

    $APINAME = 'Standards'
    foreach ($Template in $Settings.TemplateList) {
      try {
        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'ExConnectorTemplate' and RowKey eq '$($Template.value)'"
        $connectorType = (Get-AzDataTableEntity @Table -Filter $Filter).direction
        $RequestParams = (Get-AzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json
        $Existing = New-ExoRequest -ErrorAction SilentlyContinue -tenantid $Tenant -cmdlet "Get-$($ConnectorType)connector" | Where-Object -Property Identity -EQ $RequestParams.name
        if ($Existing) {
          $RequestParams | Add-Member -NotePropertyValue $Existing.Identity -NotePropertyName Identity -Force
          $GraphRequest = New-ExoRequest -tenantid $Tenant -cmdlet "Set-$($ConnectorType)connector" -cmdParams $RequestParams -useSystemMailbox $true
          Write-LogMessage -API $APINAME -tenant $Tenant -message "Updated transport rule for $($Tenant, $Settings)" -sev info
        } else {
          $GraphRequest = New-ExoRequest -tenantid $Tenant -cmdlet "New-$($ConnectorType)connector" -cmdParams $RequestParams -useSystemMailbox $true
          Write-LogMessage -API $APINAME -tenant $Tenant -message "Created transport rule for $($Tenant, $Settings)" -sev info
        }
      } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create or update Exchange Connector Rule: $ErrorMessage" -sev 'Error'
      }

    }

  }


}
