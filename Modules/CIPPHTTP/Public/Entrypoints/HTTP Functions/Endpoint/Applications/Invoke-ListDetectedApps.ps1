function Invoke-ListDetectedApps {
    <#
    .FUNCTIONALITY
        Entrypoint,TenantGroup
    .ROLE
        Endpoint.MEM.Read,Identity.Device.Read
    .DESCRIPTION
        Lists applications detected on Intune-managed devices in a tenant, one row per app name and version with the number of devices it is on, optionally including device associations. Supports UseReportDB=true to read the DetectedApps cache in the reporting database; AllTenants always reads the cache. Cached rows leave out the device list: ListDetectedAppDevices returns it per app.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    $DeviceID = $Request.Query.DeviceID
    # Also return the devices each detected app is installed on.
    $IncludeDevices = $Request.Query.includeDevices -eq $true
    # Serve from the reporting database cache instead of live Graph. Required for AllTenants.
    $UseReportDB = $Request.Query.UseReportDB -eq $true

    if (-not $TenantFilter) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'tenantFilter is required' }
            })
    }

    if ($TenantFilter -eq 'AllTenants' -or $UseReportDB) {
        $ReadApps = {
            param($Tenant)
            $CountRows = @(Get-CIPPDbItem -TenantFilter $Tenant -Type 'DetectedApps' -CountsOnly)
            if ($CountRows.Count -eq 0) {
                throw [System.Management.Automation.ItemNotFoundException]::new("No detected apps cached for $Tenant. Sync the report data first.")
            }
            $CacheTimestamp = $CountRows[0].Timestamp
            # Each row carries the app's whole device list; parse only the summary fields
            foreach ($App in New-CIPPDbRequest -TenantFilter $Tenant -Type 'DetectedApps' -Fields 'id', 'displayName', 'version', 'publisher', 'platform', 'deviceCount' -PageSize 1000) {
                $App.PSObject.Properties.Add([psnoteproperty]::new('CacheTimestamp', $CacheTimestamp))
                $App
            }
        }
        try {
            if ($Request.Query.manualPagination -eq $true) {
                # Cached rows per page, clamped between 250 and 10000. Defaults to 5000. Pages hold whole tenants.
                $PageSize = $Request.Query.PageSize -as [int]
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        # Continuation token from the previous page's Metadata.nextLink; opaque to callers.
                        Body       = Get-CIPPReportPage -TenantFilter $TenantFilter -Type 'DetectedApps' -PageSize $PageSize -ContinuationToken $Request.Query.nextLink -Report $ReadApps
                    })
            }
            if ($TenantFilter -eq 'AllTenants') {
                $Results = [System.Collections.Generic.List[object]]::new()
                $TotalTenants = 0
                $FailedTenants = 0
                foreach ($Tenant in (Get-Tenants -IncludeErrors).defaultDomainName) {
                    if (-not $Tenant) { continue }
                    try {
                        foreach ($App in (& $ReadApps $Tenant)) {
                            $App.PSObject.Properties.Add([psnoteproperty]::new('Tenant', $Tenant))
                            $Results.Add($App)
                        }
                        $TotalTenants++
                    } catch [System.Management.Automation.ItemNotFoundException] {
                        continue
                    } catch {
                        $TotalTenants++
                        $FailedTenants++
                        Write-LogMessage -API 'ListDetectedApps' -tenant $Tenant -message "Failed to read cached detected apps: $($_.Exception.Message)" -sev Warning
                    }
                }
                $StatusCode = Get-CippBulkStatusCode -Total $TotalTenants -Failed $FailedTenants
            } else {
                $Results = & $ReadApps $TenantFilter
                $StatusCode = [HttpStatusCode]::OK
            }
        } catch {
            $Results = Get-NormalizedError -Message $_.Exception.Message
            $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        }
        return ([HttpResponseContext]@{
                StatusCode = $StatusCode
                Body       = @($Results)
            })
    }

    # This is all about the deviceManagement/detectedApps endpoint
    # We need to get the detected apps for a given device or the entire tenant
    # If no device ID is provided, we need to get the detected apps for the entire tenant
    # If a device ID is provided, we need to get the detected apps for the device
    # deviceManagement/detectedApps for the entire tenant, or deviceManagement/managedDevices/$DeviceID/detectedApps for the device
    # If includeDevices is true, we can use deviceManagement/detectedApps/{id}/managedDevices to get devices where each app is installed

    try {
        # If DeviceID is provided, get detected apps for that device
        if ($DeviceID) {
            $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$([uri]::EscapeDataString($DeviceID))/detectedApps" -Tenantid $TenantFilter
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
        $StatusCode = [HttpStatusCode]::InternalServerError
        $GraphRequest = $ErrorMessage
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    }
}
