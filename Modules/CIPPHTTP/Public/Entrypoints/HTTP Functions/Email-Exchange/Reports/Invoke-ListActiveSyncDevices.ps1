function Invoke-ListActiveSyncDevices {
    <#
    .FUNCTIONALITY
        Entrypoint,TenantGroup
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Lists Exchange Online mobile devices (ActiveSync and Outlook for iOS and Android) in a tenant: the mailbox, device, access state (Allowed, Blocked, Quarantined), why that state applies (Global, Individual, DeviceRule, Policy) and whether the device is on the mailbox's allow or block list. Supports UseReportDB=true to read the reporting database cache; AllTenants always reads the cache.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    # Serve from the reporting database cache instead of live Exchange. Required for AllTenants.
    $UseReportDB = $Request.Query.UseReportDB -eq $true

    try {
        if ($TenantFilter -eq 'AllTenants' -or $UseReportDB) {
            $ReadDevices = {
                param($Tenant)
                $Rows = @(Get-CIPPDbItem -TenantFilter $Tenant -Type 'MobileDevices')
                if ($Rows.Count -eq 0) {
                    throw [System.Management.Automation.ItemNotFoundException]::new("No mobile device data cached for $Tenant. Sync the report data first.")
                }
                foreach ($Row in $Rows) {
                    if ($Row.RowKey -eq 'MobileDevices-Count') { continue }
                    $Device = [CIPP.CippJson]::ConvertFromJson($Row.Data, $null)
                    $Device.PSObject.Properties.Add([psnoteproperty]::new('CacheTimestamp', $Row.Timestamp))
                    $Device
                }
            }
            if ($Request.Query.manualPagination -eq $true) {
                # Cached rows per page, clamped between 250 and 10000. Defaults to 5000. Pages hold whole tenants.
                $PageSize = $Request.Query.PageSize -as [int]
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        # Continuation token from the previous page's Metadata.nextLink; opaque to callers.
                        Body       = Get-CIPPReportPage -TenantFilter $TenantFilter -Type 'MobileDevices' -PageSize $PageSize -ContinuationToken $Request.Query.nextLink -Report $ReadDevices
                    })
            }
            $Results = if ($TenantFilter -eq 'AllTenants') {
                foreach ($Tenant in @((Get-Tenants -IncludeErrors).defaultDomainName | Where-Object { $_ })) {
                    try {
                        foreach ($Device in (& $ReadDevices $Tenant)) {
                            $Device.PSObject.Properties.Add([psnoteproperty]::new('Tenant', $Tenant))
                            $Device
                        }
                    } catch [System.Management.Automation.ItemNotFoundException] {
                        continue
                    }
                }
            } else {
                & $ReadDevices $TenantFilter
            }
        } else {
            $Results = Get-CIPPMobileDevice -TenantFilter $TenantFilter
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })
}
