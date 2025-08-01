function Push-CippDriftManagement {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param (
        $Item
    )

    Write-Information "Received drift standard item for $($Item.Tenant)"

    try {
        $Drift = Get-CIPPDrift -TenantFilter $Item.Tenant
        if ($Drift.newDeviationsCount -gt 0) {
            $Settings = (Get-CIPPTenantAlignment -TenantFilter $Item.Tenant | Where-Object -Property standardType -EQ 'drift')
            $email = $Settings.driftAlertEmail
            $webhook = $Settings.driftAlertWebhook
            $CippConfigTable = Get-CippTable -tablename Config
            $CippConfig = Get-CIPPAzDataTableEntity @CippConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
            $CIPPURL = 'https://{0}' -f $CippConfig.Value
            $Data = $Drift.currentDeviations | ForEach-Object {
                $currentValue = if ($_.receivedValue -and $_.receivedValue.Length -gt 200) {
                    $_.receivedValue.Substring(0, 200) + '...'
                } else {
                    $_.receivedValue
                }
                [PSCustomObject]@{
                    Standard         = $_.standardDisplayName ? $_.standardDisplayName : $_.standardName
                    'Expected Value' = $_.expectedValue
                    'Current Value'  = $currentValue
                    Status           = $_.status
                }
            }

            $GenerateEmail = New-CIPPAlertTemplate -format 'html' -data $Data -CIPPURL $CIPPURL -Tenant $Item.Tenant -InputObject 'driftStandard' -AuditLogLink $drift.standardId
            $CIPPAlert = @{
                Type         = 'email'
                Title        = $GenerateEmail.title
                HTMLContent  = $GenerateEmail.htmlcontent
                TenantFilter = $Item.Tenant
            }
            Write-Host 'Going to send the mail'
            Send-CIPPAlert @CIPPAlert -altEmail $email
            $WebhookData = @{
                Title      = $GenerateEmail.title
                ActionUrl  = $GenerateEmail.ButtonUrl
                ActionText = $GenerateEmail.ButtonText
                AlertData  = $Data
                Tenant     = $Item.Tenant
            } | ConvertTo-Json -Depth 15 -Compress
            $CippAlert = @{
                Type         = 'webhook'
                Title        = $GenerateEmail.title
                JSONContent  = $WebhookData
                TenantFilter = $Item.Tenant
            }
            Write-Host 'Sending Webhook Content'
            Send-CIPPAlert @CippAlert -altWebhook $webhook
            #Always do PSA.
            $CIPPAlert = @{
                Type         = 'psa'
                Title        = $GenerateEmail.title
                HTMLContent  = $GenerateEmail.htmlcontent
                TenantFilter = $Item.Tenant
            }
            Send-CIPPAlert @CIPPAlert
            return $true
        } else {
            Write-LogMessage -API 'DriftStandards' -tenant $Item.Tenant -message "No new drift deviations found for tenant $($Item.Tenant)" -sev Info
            return $true
        }
        Write-Information "Drift management completed for tenant $($Item.Tenant)"
    } catch {
        Write-LogMessage -API 'DriftStandards' -tenant $Item.Tenant -message "Error running Drift Check for tenant $($Item.Tenant) - $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        Write-Warning "Error running drift standards for tenant $($Item.Tenant) - $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
        throw $_.Exception.Message
    }
}
