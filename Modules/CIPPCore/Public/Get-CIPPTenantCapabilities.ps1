
function Get-CIPPTenantCapabilities {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $APIName = 'Get Tenant Capabilities',
        $Headers
    )
    $ConfigTable = Get-CIPPTable -TableName 'CacheCapabilities'
    $datetime = (Get-Date).AddDays(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $ConfigEntries = Get-CIPPAzDataTableEntity @ConfigTable -Filter "RowKey eq '$TenantFilter' and PartitionKey eq 'Capabilities' and Timestamp ge datetime'$datetime'"
    if ($ConfigEntries) {
        $Org = $ConfigEntries.JSON | ConvertFrom-Json
    } else {
        $Org = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $TenantFilter
        # Save the capabilities to the cache table
        $Entity = @{
            PartitionKey = 'Capabilities'
            RowKey       = $TenantFilter
            JSON         = "$($Org | ConvertTo-Json -Compress -Depth 10)"
        }
        Add-CIPPAzDataTableEntity @ConfigTable -Entity $Entity -Force
    }
    $Plans = $Org.servicePlans | Where-Object { $_.provisioningStatus -ne 'disabled' } | Sort-Object -Property serviceplanName -Unique | Select-Object servicePlanName, provisioningStatus
    $Results = @{}
    foreach ($Plan in $Plans) {
        $Results."$($Plan.servicePlanName)" = $Plan.provisioningStatus -ne 'disabled'
    }
    [PSCustomObject]$Results
}
