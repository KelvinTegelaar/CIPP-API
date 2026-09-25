Function Invoke-ListSharepointQuota {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Admin.Read
    .DESCRIPTION
        Retrieves SharePoint Online storage quota usage for a tenant, showing used and total storage.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $Live = [bool]$Request.Query.live

    if ($Live -eq $true) {
        try {
            $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
            $extraHeaders = @{
                'Accept' = 'application/json'
            }
            $SharePointQuota = New-GraphGetRequest -extraHeaders $extraHeaders -scope "$($SharePointInfo.AdminUrl)/.default" -tenantid $TenantFilter -uri "$($SharePointInfo.AdminUrl)/_api/StorageQuotas()?api-version=1.3.2" -asapp $true -UseCertificate
            $GeoUsedStorageMB = (@($SharePointQuota) | ForEach-Object { [double]($_.GeoUsedStorageMB ?? 0) } | Measure-Object -Sum).Sum
            $TenantStorageRaw = @($SharePointQuota.TenantStorageMB | Where-Object { $_ }) | Select-Object -First 1
            $TenantStorageMB = if ($null -ne $TenantStorageRaw) { [double]$TenantStorageRaw } else { 0 }
            $GeoLocations = @()
            $GeoLocations = @(foreach ($Geo in @($SharePointQuota)) {
                if ($null -eq $Geo) { continue }
                [PSCustomObject]@{
                    GeoLocation           = $Geo.GeoLocation
                    GeoUsedStorageMB      = [double]($Geo.GeoUsedStorageMB ?? 0)
                    GeoAllocatedStorageMB = [double]($Geo.GeoAllocatedStorageMB ?? 0)
                    GeoAvailableStorageMB = [double]($Geo.GeoAvailableStorageMB ?? 0)
                }
            })

            if ($TenantStorageMB) {
                $UsedStoragePercentage = [int](($GeoUsedStorageMB / $TenantStorageMB) * 100)
            }

            $SharePointQuotaDetails = @{
                GeoUsedStorageMB = $GeoUsedStorageMB
                TenantStorageMB  = $TenantStorageMB
                Percentage       = $UsedStoragePercentage
                Dashboard        = "$($UsedStoragePercentage) / 100"
                GeoLocations     = @($GeoLocations)
            }
        } catch {
            return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = $_.Exception.Message
            })
        }

    } else {
        try {
            $SharePointQuota = (Get-CIPPDbItem -tenantFilter $TenantFilter -Type SharePointUsageReport | Where-Object { $_.RowKey -notlike '*-Count' }).Data | ConvertFrom-Json
            $SharePointQuotaDetails = [PSCustomObject]@{
                GeoUsedStorageMB = $SharePointQuota.GeoUsedStorageMB
                GeoLocations     = @($SharePointQuota.GeoLocations)
                TenantStorageMB  = $SharePointQuota.TenantStorageMB
                Percentage       = $SharePointQuota.Percentage
                Dashboard        = $SharePointQuota.Dashboard
            }
        } catch {
            return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = $_.Exception.Message
            })
        }
    }

    return ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $SharePointQuotaDetails
    })
}