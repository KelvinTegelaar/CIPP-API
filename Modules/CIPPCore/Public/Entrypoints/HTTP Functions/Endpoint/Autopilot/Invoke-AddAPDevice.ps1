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

    $TenantFilter = (Get-Tenants | Where-Object { $_.defaultDomainName -eq $Request.Body.TenantFilter.value }).customerId
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
        } until ($NewStatus.status -eq 'finished' -or $Amount -eq 4)
        if ($NewStatus.status -ne 'finished') { throw 'Could not retrieve status of import - This job might still be running. Check the autopilot device list in 10 minutes for the latest status.' }
        Write-LogMessage -headers $Request.Headers -API $APIName -tenant $($Request.body.TenantFilter.value) -message "Created Autopilot devices group. Group ID is $GroupName" -Sev 'Info'

        [PSCustomObject]@{
            Status  = 'Import Job Completed'
            Devices = @($NewStatus.devicesStatus)
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [HttpStatusCode]::InternalServerError
        [PSCustomObject]@{
            Status  = "$($Request.Body.TenantFilter.value): Failed to create autopilot devices. $($ErrorMessage.NormalizedError)"
            Devices = @()
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $($Request.Body.TenantFilter.value) -message "Failed to create autopilot devices. $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}
