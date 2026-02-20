function Invoke-ListDetectedApps {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Device.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    $DeviceID = $Request.Query.DeviceID
    $IncludeDevices = $Request.Query.includeDevices

    # This is all about the deviceManagement/detectedApps endpoint
    # We need to get the detected apps for a given device or the entire tenant
    # If no device ID is provided, we need to get the detected apps for the entire tenant
    # If a device ID is provided, we need to get the detected apps for the device
    # deviceManagement/detectedApps for the entire tenant, or deviceManagement/managedDevices/$DeviceID/detectedApps for the device
    # If includeDevices is true, we can use deviceManagement/detectedApps/{id}/managedDevices to get devices where each app is installed

    try {
        # If DeviceID is provided, get detected apps for that device
        if ($DeviceID) {
            $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$DeviceID/detectedApps" -Tenantid $TenantFilter
        }
        # If no device ID is provided, get detected apps for the entire tenant
        else {
            $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/detectedApps" -Tenantid $TenantFilter
        }

        # Ensure we return an array even if null
        if ($null -eq $GraphRequest) {
            $GraphRequest = @()
        }

        # If includeDevices is requested and we have detected apps, fetch devices for each app
        if ($IncludeDevices -and $GraphRequest -and ($GraphRequest | Measure-Object).Count -gt 0) {
            # Build bulk requests to get devices for each detected app
            $BulkRequests = [System.Collections.Generic.List[object]]::new()
            foreach ($App in $GraphRequest) {
                if ($App.id) {
                    $BulkRequests.Add(@{
                        id     = $App.id
                        method = 'GET'
                        url    = "deviceManagement/detectedApps('$($App.id)')/managedDevices"
                    })
                }
            }

            if ($BulkRequests.Count -gt 0) {
                $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter

                # Merge device information back into each detected app
                $GraphRequest = foreach ($App in $GraphRequest) {
                    $Devices = Get-GraphBulkResultByID -Results $BulkResults -ID $App.id -Value
                    if ($Devices) {
                        $App | Add-Member -NotePropertyName 'managedDevices' -NotePropertyValue $Devices -Force
                    } else {
                        $App | Add-Member -NotePropertyName 'managedDevices' -NotePropertyValue @() -Force
                    }
                    $App
                }
            }
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::OK
        $GraphRequest = $ErrorMessage
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    }
}
