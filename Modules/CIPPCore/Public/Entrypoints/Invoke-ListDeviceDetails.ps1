using namespace System.Net

Function Invoke-ListDeviceDetails {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Device.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $DeviceID = $Request.Query.DeviceID
    $DeviceName = $Request.Query.DeviceName
    $DeviceSerial = $Request.Query.DeviceSerial

    try {
        if ($DeviceID) {
            $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$DeviceID" -Tenantid $tenantfilter
        } elseif ($DeviceSerial -or $DeviceName) {
            $Found = $False
            if ($SeriaNumber -and $DeviceName) {
                $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=serialnumber eq '$DeviceSerial' and deviceName eq '$DeviceName'" -Tenantid $tenantfilter

                if (($GraphRequest | Measure-Object).count -eq 1 -and $GraphRequest.'@odata.count' -ne 0 ) {
                    $Found = $True
                }
            }
            if ($DeviceSerial -and $Found -eq $False) {
                $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=serialnumber eq '$DeviceSerial'" -Tenantid $tenantfilter
                if (($GraphRequest | Measure-Object).count -eq 1 -and $GraphRequest.'@odata.count' -ne 0 ) {
                    $Found = $True
                }
            }
            if ($DeviceName -and $Found -eq $False) {
                $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=deviceName eq '$DeviceName'" -Tenantid $tenantfilter
                if (($GraphRequest | Measure-Object).count -eq 1 -and $GraphRequest.'@odata.count' -ne 0 ) {
                    $Found = $True
                }
            }

        }

        if (!(($GraphRequest | Measure-Object).count -eq 1 -and $GraphRequest.'@odata.count' -ne 0 )) {
            $GraphRequest = $Null
        }

        if ($GraphRequest) {
            [System.Collections.Generic.List[PSCustomObject]]$BulkRequests = @(
                @{
                    id     = 'DeviceGroups'
                    method = 'GET'
                    url    = "/devices(deviceID='$($GraphRequest.azureADDeviceId)')/memberOf"
                },
                @{
                    id     = 'CompliancePolicies'
                    method = 'GET'
                    url    = "/deviceManagement/managedDevices('$($GraphRequest.id)')/deviceCompliancePolicyStates"
                },
                @{
                    id     = 'DetectedApps'
                    method = 'GET'
                    url    = "deviceManagement/managedDevices('$($GraphRequest.id)')?expand=detectedApps"
                }
            )

            $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter

            $DeviceGroups = Get-GraphBulkResultByID -Results $BulkResults -ID 'DeviceGroups' -Value
            $CompliancePolicies = Get-GraphBulkResultByID -Results $BulkResults -ID 'CompliancePolicies' -Value
            $DetectedApps = Get-GraphBulkResultByID -Results $BulkResults -ID 'DetectedApps'

            $Null = $GraphRequest | Add-Member -NotePropertyName 'DetectedApps' -NotePropertyValue ($DetectedApps.DetectedApps | Select-Object id, displayName, version)
            $Null = $GraphRequest | Add-Member -NotePropertyName 'CompliancePolicies' -NotePropertyValue ($CompliancePolicies | Select-Object id, displayname, UserPrincipalName, state)
            $Null = $GraphRequest | Add-Member -NotePropertyName 'DeviceGroups' -NotePropertyValue ($DeviceGroups | Select-Object id, displayName, description)


        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage

    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $GraphRequest
        })

}
