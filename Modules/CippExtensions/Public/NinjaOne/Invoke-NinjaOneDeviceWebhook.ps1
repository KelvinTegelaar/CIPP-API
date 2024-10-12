function Invoke-NinjaOneDeviceWebhook {
    [CmdletBinding()]
    param (
        $Data,
        $Configuration
    )
    try {
        $MappedFields = [pscustomobject]@{}
        $CIPPMapping = Get-CIPPTable -TableName CippMapping
        $Filter = "PartitionKey eq 'NinjaOneFieldMapping'"
        Get-AzDataTableEntity @CIPPMapping -Filter $Filter | Where-Object { $Null -ne $_.IntegrationId -and $_.IntegrationId -ne '' } | ForEach-Object {
            $MappedFields | Add-Member -NotePropertyName $_.RowKey -NotePropertyValue $($_.IntegrationId)
        }

        if ($MappedFields.DeviceCompliance) {
            Write-LogMessage -user $ExecutingUser -API $APIName -message "Webhook Recieved - Updating NinjaOne Device compliance for $($Data.resourceData.id) in $($Data.tenantId)" -Sev 'Info' -tenant $TenantFilter
            $tenantfilter = $Data.tenantId
            $M365DeviceID = $Data.resourceData.id

            $DeviceM365 = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/devices/$($M365DeviceID)" -Tenantid $tenantfilter

            $DeviceFilter = "PartitionKey eq '$($tenantfilter)' and RowKey eq '$($DeviceM365.deviceID)'"
            $DeviceMapTable = Get-CippTable -tablename 'NinjaOneDeviceMap'
            $Device = Get-CIPPAzDataTableEntity @DeviceMapTable -Filter $DeviceFilter

            if (($Device | Measure-Object).count -eq 1) {
                try {
                    $Token = Get-NinjaOneToken -configuration $Configuration

                    if (!$Token.access_token) {
                        Write-LogMessage -API 'NinjaOneSync' -tenant $tenantfilter -user 'CIPP' -message 'Failed to get NinjaOne Token for Device Compliance Update' -Sev 'Error'
                        return
                    }

                    if ($DeviceM365.isCompliant -eq $True) {
                        $Compliant = 'Compliant'
                    } else {
                        $Compliant = 'Non-Compliant'
                    }

                    $ComplianceBody = @{
                        "$($MappedFields.DeviceCompliance)" = $Compliant
                    } | ConvertTo-Json

                    $Null = Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/device/$($Device.NinjaOneID)/custom-fields" -Method PATCH -Body $ComplianceBody -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json'

                    Write-Host 'Updated NinjaOne Device Compliance'
                } catch {
                    $Message = if ($_.ErrorDetails.Message) {
                        Get-NormalizedError -Message $_.ErrorDetails.Message
                    } else {
                        $_.Exception.message
                    }
                    Write-Error "Failed NinjaOne Device Webhook for: $($Data | ConvertTo-Json -Depth 100) Linenumber: $($_.InvocationInfo.ScriptLineNumber) Error: $Message"
                    Write-LogMessage -API 'NinjaOneSync' -user 'CIPP' -message "Failed NinjaOne Device Webhook Linenumber: $($_.InvocationInfo.ScriptLineNumber) Error: $Message" -Sev 'Error'
                }
            } else {
                Write-LogMessage -API 'NinjaOneSync' -user 'CIPP' -message "$($DeviceM365.displayName) ($($M365DeviceID)) was not matched in Ninja for $($tenantfilter)" -Sev 'Info'
            }

        }

    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.message
        }
        Write-Error "Failed NinjaOne Device Webhook for: $($Data | ConvertTo-Json -Depth 100) Linenumber: $($_.InvocationInfo.ScriptLineNumber) Error: $Message"
        Write-LogMessage -API 'NinjaOneSync' -user 'CIPP' -message "Failed NinjaOne Device Webhook Linenumber: $($_.InvocationInfo.ScriptLineNumber) Error: $Message" -Sev 'Error'
    }



}
