function Invoke-CIPPStandardExchangeConnectorTemplate {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'ExConnector' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'ExConnector'

    if ($Settings.remediate -eq $true) {

        foreach ($Template in $Settings.TemplateList) {
            try {
                $Table = Get-CippTable -tablename 'templates'
                $Filter = "PartitionKey eq 'ExConnectorTemplate' and RowKey eq '$($Template.value)'"
                $connectorType = (Get-AzDataTableEntity @Table -Filter $Filter).direction
                $RequestParams = (Get-AzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json
                if ($RequestParams.comment) { $RequestParams.comment = Get-CIPPTextReplacement -Text $RequestParams.comment -TenantFilter $Tenant } else { $RequestParams | Add-Member -NotePropertyValue 'no comment' -NotePropertyName comment -Force }
                $Existing = New-ExoRequest -ErrorAction SilentlyContinue -tenantid $Tenant -cmdlet "Get-$($ConnectorType)connector" | Where-Object -Property Identity -EQ $RequestParams.name
                if ($Existing) {
                    $RequestParams | Add-Member -NotePropertyValue $Existing.Identity -NotePropertyName Identity -Force
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet "Set-$($ConnectorType)connector" -cmdParams $RequestParams -useSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated transport rule for $($Tenant, $Settings)" -sev info
                } else {
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet "New-$($ConnectorType)connector" -cmdParams $RequestParams -useSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created transport rule for $($Tenant, $Settings)" -sev info
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create or update Exchange Connector Rule: $ErrorMessage" -sev 'Error'
            }

        }

    }


}
