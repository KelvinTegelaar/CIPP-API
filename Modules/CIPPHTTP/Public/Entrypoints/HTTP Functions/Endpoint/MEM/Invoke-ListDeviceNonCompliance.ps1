function Invoke-ListDeviceNonCompliance {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    .DESCRIPTION
        Lists cached failing compliance settings on non-compliant Intune managed devices, one row per device per setting, from the NoncompliantDevicesAndSettingsV3 export in the CIPP reporting database. Each row carries the device's current compliance state from the ManagedDevices cache. Supports AllTenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = 'ListDeviceNonCompliance'
    $TenantFilter = $Request.Query.tenantFilter

    if (-not $TenantFilter) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'tenantFilter is required'
            })
    }

    $GetTenantRows = {
        param($Tenant, $Items)
        $Params = @{ TenantFilter = $Tenant; Type = 'IntuneNonCompliantSettings' }
        if ($null -ne $Items) { $Params.Rows = $Items }
        $Rows = @(New-CIPPDbRequest @Params)
        if (-not $Rows) { return }

        $CacheTimestamp = (Get-CIPPDbItem -TenantFilter $Tenant -Type 'IntuneNonCompliantSettings' -CountsOnly | Select-Object -First 1).Timestamp
        # The export has no device compliance state; the ManagedDevices cache tells grace period apart from non-compliant
        $States = @{}
        foreach ($Device in New-CIPPDbRequest -TenantFilter $Tenant -Type 'ManagedDevices' -Fields 'id', 'complianceState') {
            if ($Device.id) { $States["$($Device.id)"] = $Device.complianceState }
        }
        foreach ($Row in $Rows) {
            $Row | Add-Member -NotePropertyMembers ([ordered]@{
                    complianceState = $States["$($Row.deviceId)"]
                    CacheTimestamp  = $CacheTimestamp
                }) -Force
            $Row
        }
    }

    try {
        $AllResults = [System.Collections.Generic.List[object]]::new()
        $TotalTenants = 0
        $FailedTenants = 0

        if ($TenantFilter -eq 'AllTenants') {
            $ItemsByTenant = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'IntuneNonCompliantSettings' -ByTenant
            $TotalTenants = @($ItemsByTenant.Keys).Count
            foreach ($Tenant in @($ItemsByTenant.Keys)) {
                # Hand each tenant its rows and drop them here so they can be freed once processed
                $TenantItems = $ItemsByTenant[$Tenant]; $ItemsByTenant[$Tenant] = $null
                try {
                    foreach ($Row in & $GetTenantRows $Tenant $TenantItems) {
                        $Row | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                        $AllResults.Add($Row)
                    }
                } catch {
                    $FailedTenants++
                    Write-LogMessage -API $APIName -tenant $Tenant -message "Failed to read cached non-compliant settings: $($_.Exception.Message)" -sev Warning
                }
            }
        } else {
            foreach ($Row in & $GetTenantRows $TenantFilter $null) { $AllResults.Add($Row) }
        }

        $Results = @($AllResults | Sort-Object -Property deviceName, policyName, settingName)
        $StatusCode = Get-CippBulkStatusCode -Total $TotalTenants -Failed $FailedTenants
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to list non-compliant settings: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Results = @{ Error = $ErrorMessage.NormalizedError }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })
}
