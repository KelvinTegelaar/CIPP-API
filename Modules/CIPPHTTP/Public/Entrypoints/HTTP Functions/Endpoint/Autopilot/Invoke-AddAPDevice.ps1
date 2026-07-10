function Invoke-AddAPDevice {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.ReadWrite
    .DESCRIPTION
        Adds Autopilot devices to a tenant via Partner Center API
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = (Get-Tenants -TenantFilter $Request.Body.TenantFilter.value).customerId
    $GroupName = if ($Request.Body.Groupname) { $Request.Body.Groupname } else { (New-Guid).GUID }
    Write-Host $GroupName

    $rawDevices = $Request.Body.autopilotData
    $Devices = ConvertTo-Json @($rawDevices)
    $Result = try {
        $CurrentStatus = (New-GraphGetRequest -uri "https://api.partnercenter.microsoft.com/v1/customers/$TenantFilter/DeviceBatches" -scope 'https://api.partnercenter.microsoft.com/user_impersonation')
        if ($GroupName -in $CurrentStatus.items.id) {
            Write-Host 'Gonna do an update!'
            $Body = $Request.Body.autopilotData | ForEach-Object {
                $Device = $_
                [pscustomobject]@{
                    deviceBatchId       = $GroupName
                    hardwareHash        = $Device.hardwareHash
                    serialNumber        = $Device.SerialNumber
                    productKey          = $Device.productKey
                    oemManufacturerName = $Device.oemManufacturerName
                    modelName           = $Device.modelName
                }
            }
            $Body = ConvertTo-Json -Depth 10 -Compress -InputObject @($Body)
            Write-Host $Body
            $GraphRequest = (New-GraphPOSTRequest -returnHeaders $true -uri "https://api.partnercenter.microsoft.com/v1/customers/$TenantFilter/deviceBatches/$GroupName/devices" -body $Body -scope 'https://api.partnercenter.microsoft.com/user_impersonation')
        } else {
            $Body = '{"batchId":"' + $($GroupName) + '","devices":' + $Devices + '}'
            $GraphRequest = (New-GraphPOSTRequest -returnHeaders $true -uri "https://api.partnercenter.microsoft.com/v1/customers/$TenantFilter/DeviceBatches" -body $Body -scope 'https://api.partnercenter.microsoft.com/user_impersonation')
        }
        $Amount = 0
        do {
            Write-Host "Checking status of import job for $GroupName"
            $Amount++
            Start-Sleep 1
            $NewStatus = New-GraphGetRequest -uri "https://api.partnercenter.microsoft.com/v1/$($GraphRequest.Location)" -scope 'https://api.partnercenter.microsoft.com/user_impersonation'
        } until ($NewStatus.status -in @('finished', 'finished_with_errors') -or $Amount -eq 4)
        if ($NewStatus.status -notin @('finished', 'finished_with_errors')) { throw 'Could not retrieve status of import - This job might still be running. Check the autopilot device list in 10 minutes for the latest status.' }
        Write-LogMessage -headers $Headers -API $APIName -tenant $($Request.body.TenantFilter.value) -message "Created Autopilot devices group. Group ID is $GroupName" -Sev 'Info'

        # DEBUG: dump the raw status so we can inspect what Partner Center returns per device.
        Write-Host "RAW NewStatus: $($NewStatus | ConvertTo-Json -Depth 10)"

        # Build one result per device (DeviceUploadDetails) so the frontend renders a
        # single bar each, instead of flattening raw device fields into many stray bars.
        $Index = 0
        $DeviceResults = foreach ($Device in @($NewStatus.devicesStatus)) {
            $Index++
            # Hash-only uploads return no serial/productKey/deviceId; fall back to a number.
            $DeviceId = $Device.serialNumber ?? $Device.productKey ?? $Device.deviceId
            $Label = $DeviceId ?? "Device $Index"
            $IsError = $Device.status -match 'error'
            $Text = "$($Label): $($Device.status)"
            if ($IsError -and $Device.errorDescription) {
                $Text += " - $($Device.errorCode) $($Device.errorDescription)"
            }
            # Log each device with the input data that was submitted for it (matched by position).
            $InputDevice = @($rawDevices)[$Index - 1]
            Write-LogMessage -headers $Headers -API $APIName -tenant $($Request.Body.TenantFilter.value) -message "Autopilot import - $Text" -Sev $(if ($IsError) { 'Error' } else { 'Info' }) -LogData $InputDevice
            [PSCustomObject]@{
                resultText = $Text
                state      = if ($IsError) { 'error' } else { 'success' }
                copyField  = $DeviceId
                details    = $Device
            }
        }
        if (-not $DeviceResults) {
            $DeviceResults = [PSCustomObject]@{ resultText = "Import job '$($NewStatus.status)' for group $GroupName"; state = 'success' }
        }
        $StatusCode = [HttpStatusCode]::OK
        # Emit as the try block's value so the outer `$Result = try {...}` captures it.
        $DeviceResults
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [HttpStatusCode]::InternalServerError
        [PSCustomObject]@{
            resultText = "$($Request.Body.TenantFilter.value): Failed to create autopilot devices. $($ErrorMessage.NormalizedError)"
            state      = 'error'
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $($Request.Body.TenantFilter.value) -message "Failed to create autopilot devices. $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = @($Result) }
        })
}
