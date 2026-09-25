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

        if ($MappedFields.DeviceCompliance -or $MappedFields.DeviceNonCompliantSettings) {
            Write-LogMessage -Headers $Headers -API 'NinjaDeviceCompliance' -message "Webhook Received - Updating NinjaOne Device compliance for $($Data.resourceData.id) in $($Data.tenantId)" -Sev 'Info' -tenant $TenantFilter
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
                        Write-LogMessage -API 'NinjaOneSync' -tenant $tenantfilter -message 'Failed to get NinjaOne Token for Device Compliance Update' -Sev 'Error'
                        return
                    }

                    $ComplianceBody = @{}

                    if ($MappedFields.DeviceCompliance) {
                        if ($DeviceM365.isCompliant -eq $True) {
                            $Compliant = 'Compliant'
                        } else {
                            $Compliant = 'Non-Compliant'
                        }
                        $ComplianceBody[$MappedFields.DeviceCompliance] = $Compliant
                    }

                    if ($MappedFields.DeviceNonCompliantSettings) {
                        # A compliant device clears the field. A non-compliant one gets its failing settings looked up in Intune.
                        $NonCompliantSettings = $null
                        if ($DeviceM365.isCompliant -ne $True) {
                            $ManagedDeviceId = $Device.M365ID
                            if (-not $ManagedDeviceId) {
                                # Device map rows written before the Intune id was stored: resolve it from the Entra device id.
                                $ManagedDeviceId = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=azureADDeviceId eq '$($DeviceM365.deviceId)'&`$select=id" -Tenantid $tenantfilter | Select-Object -First 1).id
                            }
                            if ($ManagedDeviceId) {
                                $NonCompliantSettings = (Get-NinjaOneDeviceNonCompliantSettings -TenantFilter $tenantfilter -ManagedDeviceIds @($ManagedDeviceId))["$ManagedDeviceId"]
                            }
                        }
                        $ComplianceBody[$MappedFields.DeviceNonCompliantSettings] = $NonCompliantSettings
                    }

                    $ComplianceBodyJson = $ComplianceBody | ConvertTo-Json

                    $Null = Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/device/$($Device.NinjaOneID)/custom-fields" -Method PATCH -Body $ComplianceBodyJson -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json; charset=utf-8'

                    Write-Host 'Updated NinjaOne Device Compliance'
                } catch {
                    $Message = if ($_.ErrorDetails.Message) {
                        Get-NormalizedError -Message $_.ErrorDetails.Message
                    } else {
                        $_.Exception.message
                    }
                    Write-Error "Failed NinjaOne Device Webhook for: $($Data | ConvertTo-Json -Depth 100) Linenumber: $($_.InvocationInfo.ScriptLineNumber) Error: $Message"
                    Write-LogMessage -API 'NinjaOneSync' -message "Failed NinjaOne Device Webhook Linenumber: $($_.InvocationInfo.ScriptLineNumber) Error: $Message" -Sev 'Error'
                }
            } else {
                Write-LogMessage -API 'NinjaOneSync' -message "$($DeviceM365.displayName) ($($M365DeviceID)) was not matched in Ninja for $($tenantfilter)" -Sev 'Info'
            }

        }

    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.message
        }
        Write-Error "Failed NinjaOne Device Webhook for: $($Data | ConvertTo-Json -Depth 100) Linenumber: $($_.InvocationInfo.ScriptLineNumber) Error: $Message"
        Write-LogMessage -API 'NinjaOneSync' -message "Failed NinjaOne Device Webhook Linenumber: $($_.InvocationInfo.ScriptLineNumber) Error: $Message" -Sev 'Error'
    }



}
