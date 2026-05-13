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
            $Settings = $Drift.driftSettings
            $email = $Settings.driftAlertEmail
            $webhook = $Settings.driftAlertWebhook
            $CippConfigTable = Get-CippTable -tablename Config
            $CippConfig = Get-CIPPAzDataTableEntity @CippConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
            $CIPPURL = 'https://{0}' -f $CippConfig.Value

            # Process deviations more efficiently with foreach instead of ForEach-Object
            $Data = foreach ($deviation in $Drift.currentDeviations) {
                $currentValue = if ($deviation.receivedValue -and $deviation.receivedValue.Length -gt 200) {
                    $deviation.receivedValue.Substring(0, 200) + '...'
                } else {
                    $deviation.receivedValue
                }
                [PSCustomObject]@{
                    Standard         = $deviation.standardDisplayName ? $deviation.standardDisplayName : $deviation.standardName
                    'Expected Value' = $deviation.expectedValue
                    'Current Value'  = $currentValue
                    Status           = $deviation.status
                }
            }

            $GenerateEmail = New-CIPPAlertTemplate -format 'html' -data $Data -CIPPURL $CIPPURL -Tenant $Item.Tenant -InputObject 'driftStandard' -AuditLogLink $drift.standardId

            # Check if notifications are disabled (default to false if not set)
            if (-not $Settings.driftAlertDisableEmail) {
                # Send email alert if configured
                $CIPPAlert = @{
                    Type         = 'email'
                    Title        = $GenerateEmail.title
                    HTMLContent  = $GenerateEmail.htmlcontent
                    TenantFilter = $Item.Tenant
                }
                Write-Information "Sending email alert for tenant $($Item.Tenant)"
                Send-CIPPAlert @CIPPAlert -altEmail $email
                
                # Send webhook alert if configured
                $WebhookData = @{
                    Title      = $GenerateEmail.title
                    ActionUrl  = $GenerateEmail.ButtonUrl
                    ActionText = $GenerateEmail.ButtonText
                    AlertData  = $Data
                    Tenant     = $Item.Tenant
                } | ConvertTo-Json -Depth 5 -Compress
                $CippAlert = @{
                    Type         = 'webhook'
                    Title        = $GenerateEmail.title
                    JSONContent  = $WebhookData
                    TenantFilter = $Item.Tenant
                }
                Write-Information "Sending webhook alert for tenant $($Item.Tenant)"
                Send-CIPPAlert @CippAlert -altWebhook $webhook
                
                # Send PSA alert
                $CIPPAlert = @{
                    Type         = 'psa'
                    Title        = $GenerateEmail.title
                    HTMLContent  = $GenerateEmail.htmlcontent
                    TenantFilter = $Item.Tenant
                }
                Send-CIPPAlert @CIPPAlert
            } else {
                Write-Information "All notifications disabled for tenant $($Item.Tenant)"
            }
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
