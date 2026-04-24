function Set-CIPPDBCacheDetectedApps {
    <#
    .SYNOPSIS
        Caches all detected apps for a tenant, including devices that have each app

    .PARAMETER TenantFilter
        The tenant to cache detected apps for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching detected apps' -sev Debug

        # Step 1: Get first page with noPaginate to avoid sequential chase, and read @odata.count
        $FirstPageResult = New-GraphBulkRequest -Requests @(
            [PSCustomObject]@{
                id     = 'detectedApps-0'
                method = 'GET'
                url    = 'deviceManagement/detectedApps'
            }
        ) -tenantid $TenantFilter -NoPaginateIds @('detectedApps-0')

        $FirstResponse = ($FirstPageResult | Where-Object { $_.id -eq 'detectedApps-0' }).body
        $TotalCount = $FirstResponse.'@odata.count'
        $DetectedApps = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($app in $FirstResponse.value) { $DetectedApps.Add($app) }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "DetectedApps total count: $TotalCount, first page: $($DetectedApps.Count)" -sev Debug

        # Step 2: If more pages exist, pre-calculate all skip offsets and fire as batches
        if ($FirstResponse.'@odata.nextLink' -and $TotalCount -gt 50) {
            $SkipRequests = [System.Collections.Generic.List[PSCustomObject]]::new()
            for ($skip = 50; $skip -lt $TotalCount; $skip += 50) {
                $SkipRequests.Add([PSCustomObject]@{
                    id     = "detectedApps-$skip"
                    method = 'GET'
                    url    = "deviceManagement/detectedApps?`$skip=$skip"
                })
            }
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Fetching $($SkipRequests.Count) remaining pages in bulk" -sev Debug

            # New-GraphBulkRequest auto-batches into groups of 20, NoPaginateIds prevents chasing empty nextLinks
            $SkipResults = New-GraphBulkRequest -Requests @($SkipRequests) -tenantid $TenantFilter -NoPaginateIds @($SkipRequests.id)

            foreach ($Result in $SkipResults) {
                if ($Result.status -eq 200 -and $Result.body.value) {
                    foreach ($app in $Result.body.value) { $DetectedApps.Add($app) }
                }
            }
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Retrieved $($DetectedApps.Count) detected apps (expected $TotalCount)" -sev Debug

        if ($DetectedApps.Count -eq 0) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DetectedApps' -Data @()
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DetectedApps' -Data @() -Count
            return
        }

        # Step 3: Bulk fetch managed devices for each app (unchanged from original)
        $DeviceRequests = $DetectedApps | Where-Object { $_.id } | ForEach-Object {
            [PSCustomObject]@{
                id     = $_.id
                method = 'GET'
                url    = "deviceManagement/detectedApps('$($_.id)')/managedDevices"
            }
        }

        if ($DeviceRequests) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Fetching devices for $($DetectedApps.Count) detected apps" -sev Debug
            $DeviceResults = New-GraphBulkRequest -Requests @($DeviceRequests) -tenantid $TenantFilter

            # Add devices to each detected app object
            $DetectedAppsWithDevices = foreach ($App in $DetectedApps) {
                $Devices = Get-GraphBulkResultByID -Results $DeviceResults -ID $App.id -Value
                $App | Add-Member -NotePropertyName 'managedDevices' -NotePropertyValue ($Devices ?? @()) -Force
                $App
            }

            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DetectedApps' -Data $DetectedAppsWithDevices
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DetectedApps' -Data $DetectedAppsWithDevices -Count
            $DetectedApps = $null
            $DetectedAppsWithDevices = $null
        } else {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DetectedApps' -Data $DetectedApps
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DetectedApps' -Data $DetectedApps -Count
            $DetectedApps = $null
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached detected apps with devices successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache detected apps: $($_.Exception.Message)" -sev Error
    }
}
