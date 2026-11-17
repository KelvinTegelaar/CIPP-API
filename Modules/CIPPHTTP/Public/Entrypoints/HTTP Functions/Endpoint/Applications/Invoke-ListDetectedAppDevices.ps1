function Invoke-ListDetectedAppDevices {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read,Identity.Device.Read
    .DESCRIPTION
        Lists Intune-managed devices that have a specific detected application installed, identified by App ID. Supports UseReportDB=true to read the device list from the DetectedApps cache, where AppID is the id from the cached ListDetectedApps rows. Devices are filled in with Entra device ID, compliance state and last sync from the ManagedDevices cache when it has them.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    $AppID = $Request.Query.AppID
    # Read the device list from the reporting database cache instead of live Graph.
    $UseReportDB = $Request.Query.UseReportDB -eq $true

    if (-not $AppID) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'AppID is required' } })
    }
    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'A single tenantFilter is required' } })
    }

    try {
        if ($UseReportDB) {
            $Tenant = @(Get-Tenants -TenantFilter $TenantFilter)
            if ($Tenant.Count -eq 0) {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = @{ Results = "Tenant $TenantFilter not found" } })
            }
            # Add-CIPPDbItem's RowKey sanitising
            $RowKey = [regex]::Replace([regex]::Replace("DetectedApps-$AppID", '[/\\#?]', '_'), '[\u0000-\u001F\u007F-\u009F]', '')
            $Table = Get-CIPPTable -TableName 'CippReportingDB'
            $Filter = "PartitionKey eq '{0}' and RowKey eq '{1}'" -f (ConvertTo-CIPPODataFilterValue -Value $Tenant[0].defaultDomainName -Type String), (ConvertTo-CIPPODataFilterValue -Value $RowKey -Type String)
            $Rows = @(Get-CIPPAzDataTableEntity @Table -Filter $Filter)
            if ($Rows.Count -eq 0) {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = @{ Results = "App $AppID is not in the detected apps cache for $TenantFilter. Sync the report data first." } })
            }
            $Devices = @([CIPP.CippJson]::ConvertFromJson($Rows[0].Data, [string[]]@('managedDevices')).managedDevices)
        } else {
            $Devices = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/detectedApps/$([uri]::EscapeDataString($AppID))/managedDevices" -Tenantid $TenantFilter)
        }

        # The app inventory has no Entra device ID, which adding devices to a group needs
        $ManagedDevices = @{}
        try {
            foreach ($Device in New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ManagedDevices' -Fields 'id', 'deviceName', 'userPrincipalName', 'operatingSystem', 'osVersion', 'complianceState', 'lastSyncDateTime', 'azureADDeviceId') {
                if ($Device.id) { $ManagedDevices[[string]$Device.id] = $Device }
            }
        } catch {
            Write-Information "No managed device cache to enrich detected app devices for $($TenantFilter): $($_.Exception.Message)"
        }

        $Results = foreach ($Device in $Devices) {
            if ($null -eq $Device) { continue }
            $Managed = $ManagedDevices[[string]$Device.id]
            [pscustomobject]@{
                id                = $Device.id
                deviceName        = $Device.deviceName ?? $Managed.deviceName
                userPrincipalName = $Device.userPrincipalName ?? $Managed.userPrincipalName
                operatingSystem   = $Device.operatingSystem ?? $Managed.operatingSystem ?? $Device.platform
                osVersion         = $Device.osVersion ?? $Managed.osVersion
                complianceState   = $Device.complianceState ?? $Managed.complianceState
                lastSyncDateTime  = $Device.lastSyncDateTime ?? $Managed.lastSyncDateTime
                azureADDeviceId   = $Device.azureADDeviceId ?? $Managed.azureADDeviceId
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($Results)
    }
}
