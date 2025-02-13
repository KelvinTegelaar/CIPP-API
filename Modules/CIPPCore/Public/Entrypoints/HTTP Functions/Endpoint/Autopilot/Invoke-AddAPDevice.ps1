using namespace System.Net

Function Invoke-AddAPDevice {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    $TenantFilter = (Get-Tenants | Where-Object { $_.defaultDomainName -eq $Request.body.TenantFilter.value }).customerId
    $GroupName = if ($Request.body.Groupname) { $Request.body.Groupname } else { (New-Guid).GUID }
    Write-Host $GroupName
    $rawDevices = $request.body.autopilotData
    $Devices = ConvertTo-Json @($rawDevices)
    $Result = try {
        $CurrentStatus = (New-GraphgetRequest -uri "https://api.partnercenter.microsoft.com/v1/customers/$tenantfilter/DeviceBatches" -scope 'https://api.partnercenter.microsoft.com/user_impersonation')
        if ($groupname -in $CurrentStatus.items.id) {
            Write-Host 'Gonna do an update!'
            $body = $request.body.autopilotData | ForEach-Object {
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
            $body = ConvertTo-Json -Depth 10 -Compress -InputObject @($body)
            Write-Host $body
            $GraphRequest = (New-GraphPostRequest -returnHeaders $true -uri "https://api.partnercenter.microsoft.com/v1/$($CurrentStatus.items.deviceslink.uri)" -body $body -scope 'https://api.partnercenter.microsoft.com/user_impersonation')
        } else {
            $body = '{"batchId":"' + $($GroupName) + '","devices":' + $Devices + '}'
            $GraphRequest = (New-GraphPostRequest -returnHeaders $true -uri "https://api.partnercenter.microsoft.com/v1/customers/$TenantFilter/DeviceBatches" -body $body -scope 'https://api.partnercenter.microsoft.com/user_impersonation')
        }
        $Amount = 0
        do {
            Write-Host "Checking status of import job for $GroupName"
            $amount ++
            Start-Sleep 1
            $NewStatus = New-GraphgetRequest -uri "https://api.partnercenter.microsoft.com/v1/$($GraphRequest.Location)" -scope 'https://api.partnercenter.microsoft.com/user_impersonation'
        } until ($Newstatus.status -eq 'finished' -or $amount -eq 4)
        if ($NewStatus.status -ne 'finished') { throw 'Could not retrieve status of import - This job might still be running. Check the autopilot device list in 10 minutes for the latest status.' }
        Write-LogMessage -headers $Request.Headers -API $APIName -tenant $($Request.body.TenantFilter.value) -message "Created Autopilot devices group. Group ID is $GroupName" -Sev 'Info'

        [PSCustomObject]@{
            Status  = 'Import Job Completed'
            Devices = @($NewStatus.devicesStatus)
        }
    } catch {
        [PSCustomObject]@{
            Status  = "$($Request.body.TenantFilter.value): Failed to create autopilot devices. $($_.Exception.Message)"
            Devices = @()
        }
        Write-LogMessage -headers $Request.Headers -API $APIName -tenant $($Request.body.TenantFilter.value) -message "Failed to create autopilot devices. $($_.Exception.Message)" -Sev 'Error'
    }

    $body = [pscustomobject]@{'Results' = $Result }
    Write-Host $body
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body

        })

}
