
function Get-CIPPTenantCapabilities {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $APIName = 'Get Tenant Capabilities',
        $Headers
    )
    # License checks call this for every standard and test: one read per tenant per worker every few minutes
    $script:CIPPTenantCapabilitiesCache ??= @{}
    $CacheKey = "$TenantFilter"
    $Cached = $script:CIPPTenantCapabilitiesCache[$CacheKey]
    if ($Cached -and $Cached.Expires -gt [datetime]::UtcNow) {
        if ($Cached.Error) { throw $Cached.Error }
        return $Cached.Value
    }

    $ConfigTable = Get-CIPPTable -TableName 'CacheCapabilities'
    $datetime = (Get-Date).AddDays(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $ConfigEntries = Get-CIPPAzDataTableEntity @ConfigTable -Filter "RowKey eq '$TenantFilter' and PartitionKey eq 'Capabilities' and Timestamp ge datetime'$datetime'"
    if ($ConfigEntries) {
        $Org = [CIPP.CippJson]::ConvertFromJson("$($ConfigEntries.JSON)")
    } else {
        try {
            $Org = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $TenantFilter
        } catch {
            # A tenant without a token fails the same way for every caller in a run; don't re-request it per call.
            $script:CIPPTenantCapabilitiesCache[$CacheKey] = @{ Error = $_; Expires = [datetime]::UtcNow.AddMinutes(2) }
            throw
        }
        # Save the capabilities to the cache table
        $Entity = @{
            PartitionKey = 'Capabilities'
            RowKey       = $TenantFilter
            JSON         = "$($Org | ConvertTo-Json -Compress -Depth 10)"
        }
        Add-CIPPAzDataTableEntity @ConfigTable -Entity $Entity -Force
    }
    $Results = @{}
    foreach ($Plan in $Org.servicePlans) {
        if ($Plan.provisioningStatus -ne 'disabled') { $Results["$($Plan.servicePlanName)"] = $true }
    }
    $Capabilities = [PSCustomObject]$Results
    $script:CIPPTenantCapabilitiesCache[$CacheKey] = @{ Value = $Capabilities; Expires = [datetime]::UtcNow.AddMinutes(5) }
    $Capabilities
}
