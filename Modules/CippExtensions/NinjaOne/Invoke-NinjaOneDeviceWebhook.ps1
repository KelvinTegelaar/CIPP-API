function Invoke-NinjaOneDeviceWebhook {
    [CmdletBinding()]
    param (
        $Data,
        $Configuration
    )
    try {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Webhook Recieved - Updating NinjaOne Device compliance for $($Data.resourceData.id) in $($Data.tenantId)" -Sev "Info" -tenant $TenantFilter
        $MappedFields = [pscustomobject]@{}
        $CIPPMapping = Get-CIPPTable -TableName CippMapping
        $Filter = "PartitionKey eq 'NinjaFieldMapping'"
        Get-AzDataTableEntity @CIPPMapping -Filter $Filter | Where-Object { $Null -ne $_.NinjaOne -and $_.NinjaOne -ne '' } | ForEach-Object {
            $MappedFields | Add-Member -NotePropertyName $_.RowKey -NotePropertyValue $($_.NinjaOne)
        }

        if ($MappedFields.DeviceCompliance) {
            $tenantfilter = $Data.tenantId
            $M365DeviceID = $Data.resourceData.id

            $DeviceM365 = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/devices/$($M365DeviceID)" -Tenantid $tenantfilter
   
            $DeviceFilter = "PartitionKey eq '$($tenantfilter)' and RowKey eq '$($DeviceM365.deviceID)'"
            $DeviceMapTable = Get-CippTable -tablename 'NinjaOneDeviceMap'
            $Device = Get-CIPPAzDataTableEntity @DeviceMapTable -Filter $DeviceFilter
        
            if (($Device | Measure-Object).count -eq 1) {
                $Token = Get-NinjaOneToken -configuration $Configuration              
                
                if ($DeviceM365.isCompliant -eq $True) {
                    $Compliant = 'Compliant'
                } else {
                    $Compliant = 'Non-Compliant'
                }

                $ComplianceBody = @{
                    "$($MappedFields.DeviceCompliance)" = $Compliant
                } | ConvertTo-Json

                $Null = Invoke-WebRequest -uri "https://$($Configuration.Instance)/api/v2/device/$($Device.NinjaOneID)/custom-fields" -Method PATCH -Body $ComplianceBody -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json'
            
                Write-Host "Updated NinjaOne Device Compliance"
             

            } else {
                Write-LogMessage -API 'NinjaOneSync' -user 'CIPP' -message "$($DeviceM365.displayName) ($($M365DeviceID)) was not matched in Ninja for $($tenantfilter)" -Sev 'Info'
            }

        }
        
    } catch {
        Write-Error "Failed NinjaOne Device Webhook for: $($Data | ConvertTo-Json -depth 100) Linenumber: $($_.InvocationInfo.ScriptLineNumber) Error: $($_.Exception.message)"
        Write-LogMessage -API 'NinjaOneSync' -user 'CIPP' -message "Failed NinjaOne Device Webhook Linenumber: $($_.InvocationInfo.ScriptLineNumber) Error: $($_.Exception.message)" -Sev 'Error'
    }
        

   
}