
function Get-CIPPTenantCapabilities {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $APIName = 'Get Tenant Capabilities',
        $ExecutingUser
    )

    $Org = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/organization' -tenantid $TenantFilter
    $Plans = $Org.assignedPlans | Where-Object { $_.capabilityStatus -eq 'Enabled' } | Sort-Object -Property service -Unique | Select-Object capabilityStatus, service

    $Results = @{}
    foreach ($Plan in $Plans) {
        $Results."$($Plan.service)" = $Plan.capabilityStatus -eq 'Enabled'
    }
    [PSCustomObject]$Results
}
