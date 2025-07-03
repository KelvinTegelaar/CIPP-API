using namespace System.Net

function Invoke-ListDeviceDetails {
    <#
    .SYNOPSIS
    List detailed device information including groups, compliance policies, and detected apps
    
    .DESCRIPTION
    Retrieves comprehensive device information including device groups, compliance policies, and detected applications using Microsoft Graph API with bulk requests for efficiency.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Device.Read
        
    .NOTES
    Group: Device Management
    Summary: List Device Details
    Description: Retrieves comprehensive device information including device groups, compliance policies, and detected applications using Microsoft Graph API with bulk requests for efficiency.
    Tags: Device Management,Compliance,Applications,Graph API
    Parameter: tenantFilter (string) [query] - Target tenant identifier
    Parameter: DeviceID (string) [query] - Device unique identifier
    Parameter: DeviceName (string) [query] - Device name for searching
    Parameter: DeviceSerial (string) [query] - Device serial number for searching
    Response: Returns a device object with the following properties:
    Response: - Standard device properties (id, deviceName, serialNumber, etc.)
    Response: - DetectedApps (array): Array of detected applications with id, displayName, and version
    Response: - CompliancePolicies (array): Array of compliance policies with id, displayName, UserPrincipalName, and state
    Response: - DeviceGroups (array): Array of device groups with id, displayName, and description
    Response: On error: Error message with HTTP 403 status
    Example: {
      "id": "12345678-1234-1234-1234-123456789012",
      "deviceName": "DESKTOP-ABC123",
      "serialNumber": "ABC123456789",
      "azureADDeviceId": "87654321-4321-4321-4321-210987654321",
      "DetectedApps": [
        {
          "id": "app-123",
          "displayName": "Microsoft Teams",
          "version": "1.0.0.0"
        }
      ],
      "CompliancePolicies": [
        {
          "id": "policy-123",
          "displayName": "Windows 10 Compliance Policy",
          "UserPrincipalName": "john.doe@contoso.com",
          "state": "compliant"
        }
      ],
      "DeviceGroups": [
        {
          "id": "group-123",
          "displayName": "Windows Devices",
          "description": "All Windows devices"
        }
      ]
    }
    Error: Returns error details if the operation fails to retrieve device details.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # XXX Seems to be an unused endpoint? -Bobby

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $DeviceID = $Request.Query.DeviceID
    $DeviceName = $Request.Query.DeviceName
    $DeviceSerial = $Request.Query.DeviceSerial

    try {
        if ($DeviceID) {
            $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$DeviceID" -Tenantid $TenantFilter
        }
        elseif ($DeviceSerial -or $DeviceName) {
            $Found = $False
            if ($DeviceSerial -and $DeviceName) {
                $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=serialnumber eq '$DeviceSerial' and deviceName eq '$DeviceName'" -Tenantid $TenantFilter

                if (($GraphRequest | Measure-Object).count -eq 1 -and $GraphRequest.'@odata.count' -ne 0 ) {
                    $Found = $True
                }
            }
            if ($DeviceSerial -and $Found -eq $False) {
                $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=serialnumber eq '$DeviceSerial'" -Tenantid $TenantFilter
                if (($GraphRequest | Measure-Object).count -eq 1 -and $GraphRequest.'@odata.count' -ne 0 ) {
                    $Found = $True
                }
            }
            if ($DeviceName -and $Found -eq $False) {
                $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=deviceName eq '$DeviceName'" -Tenantid $TenantFilter
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
            $Null = $GraphRequest | Add-Member -NotePropertyName 'CompliancePolicies' -NotePropertyValue ($CompliancePolicies | Select-Object id, displayName, UserPrincipalName, state)
            $Null = $GraphRequest | Add-Member -NotePropertyName 'DeviceGroups' -NotePropertyValue ($DeviceGroups | Select-Object id, displayName, description)


        }

        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
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
