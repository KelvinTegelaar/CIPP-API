function Invoke-CIPPStandardTransportRuleTemplate {
  <#
    .FUNCTIONALITY
    Internal
    #>
  param($Tenant, $Settings)
  If ($Settings.remediate -eq $true) {

    foreach ($Template in $Settings.TemplateList) {
      Write-Host "working on $($Template.value)"
      $Table = Get-CippTable -tablename 'templates'
      $Filter = "PartitionKey eq 'TransportTemplate' and RowKey eq '$($Template.value)'"
      $RequestParams = (Get-AzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json
      $Existing = New-ExoRequest -ErrorAction SilentlyContinue -tenantid $Tenant -cmdlet 'Get-TransportRule' -useSystemMailbox $true | Where-Object -Property Identity -EQ $RequestParams.name


      try {
        if ($Existing) {
          Write-Host 'Found existing'
          $RequestParams | Add-Member -NotePropertyValue $RequestParams.name -NotePropertyName Identity
          $GraphRequest = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-TransportRule' -cmdParams ($RequestParams | Select-Object -Property * -ExcludeProperty GUID, Comments, HasSenderOverride, ExceptIfHasSenderOverride, ExceptIfMessageContainsDataClassifications, MessageContainsDataClassifications, UseLegacyRegex) -useSystemMailbox $true
          Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully set transport rule for $tenant" -sev 'Info'
        } else {
          Write-Host 'Creating new'
          $GraphRequest = New-ExoRequest -tenantid $Tenant -cmdlet 'New-TransportRule' -cmdParams ($RequestParams | Select-Object -Property * -ExcludeProperty GUID, Comments, HasSenderOverride, ExceptIfHasSenderOverride, ExceptIfMessageContainsDataClassifications, MessageContainsDataClassifications, UseLegacyRegex) -useSystemMailbox $true
          Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully created transport rule for $tenant" -sev 'Info'
        }

        Write-LogMessage -API $APINAME -tenant $Tenant -message "Created transport rule for $($tenantfilter)" -sev 'Debug'
      } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not create transport rule for $($tenantfilter): $ErrorMessage" -sev 'Error'
      }
    }
  }
}
