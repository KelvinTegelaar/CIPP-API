
function Get-CIPPTenantCapabilities {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $APIName = 'Get Tenant Capabilities',
        $Headers
    )

    $Org = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $TenantFilter
    $Plans = $Org.servicePlans | Where-Object { $_.provisioningStatus -eq 'Success' } | Sort-Object -Property serviceplanName -Unique | Select-Object servicePlanName, provisioningStatus
    $Results = @{}
    foreach ($Plan in $Plans) {
        $Results."$($Plan.servicePlanName)" = $Plan.provisioningStatus -eq 'Success'
    }
    [PSCustomObject]$Results
}
