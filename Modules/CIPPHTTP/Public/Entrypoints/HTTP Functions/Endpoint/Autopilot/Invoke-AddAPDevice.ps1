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
    $Scope = 'https://api.partnercenter.microsoft.com/user_impersonation'

    $rawDevices = @($Request.Body.autopilotData)
    # One device shape for both the create and the append call. Empty cells from the CSV/manual
    # import are dropped so Partner Center only sees the identifiers that were actually supplied.
    $Devices = @($rawDevices | ForEach-Object {
            $Device = [ordered]@{}
            foreach ($Property in $_.PSObject.Properties) {
                if (-not [string]::IsNullOrWhiteSpace($Property.Value)) { $Device[$Property.Name] = $Property.Value }
            }
            [pscustomobject]$Device
        })

    $Result = try {
        $CurrentStatus = (New-GraphGetRequest -uri "https://api.partnercenter.microsoft.com/v1/customers/$TenantFilter/DeviceBatches" -scope $Scope)
        # Batch ids are exact strings in Partner Center, so reuse its spelling rather than the user's.
        $ExistingBatch = @($CurrentStatus.items) | Where-Object { $_.id -eq $GroupName } | Select-Object -First 1
        if ($ExistingBatch) {
            $GroupName = $ExistingBatch.id
            Write-Information "Appending $($Devices.Count) device(s) to existing Partner Center batch '$GroupName'"
            $Body = ConvertTo-Json -InputObject $Devices -Depth 10 -Compress
            $GraphRequest = (New-GraphPOSTRequest -returnHeaders $true -uri "https://api.partnercenter.microsoft.com/v1/customers/$TenantFilter/deviceBatches/$([uri]::EscapeDataString($GroupName))/devices" -body $Body -scope $Scope)
            $LogText = "Added $($Devices.Count) Autopilot device(s) to existing batch $GroupName"
        } else {
            Write-Information "Creating Partner Center batch '$GroupName' with $($Devices.Count) device(s)"
            $Body = @{ batchId = $GroupName; devices = $Devices } | ConvertTo-Json -Depth 10 -Compress
            $GraphRequest = (New-GraphPOSTRequest -returnHeaders $true -uri "https://api.partnercenter.microsoft.com/v1/customers/$TenantFilter/DeviceBatches" -body $Body -scope $Scope)
            $LogText = "Created Autopilot batch $GroupName with $($Devices.Count) device(s)"
        }

        # Appending to an existing batch has to dedupe against it and is slower than a fresh batch,
        # so give Partner Center up to ~30s before handing the wait back to the user.
        $Amount = 0
        do {
            $Amount++
            Start-Sleep 2
            $NewStatus = New-GraphGetRequest -uri "https://api.partnercenter.microsoft.com/v1/$($GraphRequest.Location)" -scope $Scope
        } until ($NewStatus.status -in @('finished', 'finished_with_errors') -or $Amount -ge 15)

        if ($NewStatus.status -notin @('finished', 'finished_with_errors')) {
            $Text = "Import job for batch '$GroupName' is still processing (status: $($NewStatus.status)). Partner Center usually finishes within 10 minutes; check the Autopilot Devices list rather than resubmitting."
            Write-LogMessage -headers $Headers -API $APIName -tenant $($Request.Body.TenantFilter.value) -message $Text -Sev 'Warning'
            $StatusCode = [HttpStatusCode]::OK
            [PSCustomObject]@{ resultText = $Text; state = 'warning' }
        } else {
            Write-LogMessage -headers $Headers -API $APIName -tenant $($Request.body.TenantFilter.value) -message $LogText -Sev 'Info'

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
                $InputDevice = $rawDevices[$Index - 1]
                Write-LogMessage -headers $Headers -API $APIName -tenant $($Request.Body.TenantFilter.value) -message "Autopilot import - $Text" -Sev $(if ($IsError) { 'Error' } else { 'Info' }) -LogData $InputDevice
                [PSCustomObject]@{
                    resultText = $Text
                    state      = if ($IsError) { 'error' } else { 'success' }
                    copyField  = $DeviceId
                    details    = $Device
                }
            }
            if (-not $DeviceResults) {
                $DeviceResults = [PSCustomObject]@{ resultText = "Import job '$($NewStatus.status)' for batch $GroupName"; state = 'success' }
            }
            $StatusCode = [HttpStatusCode]::OK
            # Emit as the try block's value so the outer `$Result = try {...}` captures it.
            $DeviceResults
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [HttpStatusCode]::InternalServerError
        [PSCustomObject]@{
            resultText = "$($Request.Body.TenantFilter.value): Failed to add autopilot devices to batch '$GroupName'. $($ErrorMessage.NormalizedError)"
            state      = 'error'
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $($Request.Body.TenantFilter.value) -message "Failed to add autopilot devices to batch '$GroupName'. $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = @($Result) }
        })
}
