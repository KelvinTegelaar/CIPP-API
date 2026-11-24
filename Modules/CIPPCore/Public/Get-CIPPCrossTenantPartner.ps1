function Get-CIPPCrossTenantPartner {
    <#
    .SYNOPSIS
        Lists a tenant's cross-tenant access partner organisations with their names
    .DESCRIPTION
        Each partner carries id (its tenant ID, so cache rows keep a stable key), partnerName and
        partnerDomain, looked up through the partner tenant. A failed name lookup leaves the names
        empty rather than failing the list.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $Partners = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/partners' -tenantid $TenantFilter)
    if ($Partners.Count -eq 0) { return }

    $Info = @{}
    $Requests = foreach ($Partner in $Partners) {
        @{ id = $Partner.tenantId; method = 'GET'; url = "tenantRelationships/findTenantInformationByTenantId(tenantId='$($Partner.tenantId)')" }
    }
    try {
        foreach ($Result in @(New-GraphBulkRequest -Requests @($Requests) -tenantid $env:TenantID -NoAuthCheck $true -asapp $true)) {
            if ($Result.body.displayName) { $Info[[string]$Result.id] = $Result.body }
        }
    } catch {
        Write-LogMessage -API 'CrossTenantAccess' -tenant $TenantFilter -message "Could not look up partner organisation names: $($_.Exception.Message)" -sev Warning
    }

    foreach ($Partner in $Partners) {
        $Lookup = $Info[[string]$Partner.tenantId]
        $Partner.PSObject.Properties.Add([psnoteproperty]::new('id', $Partner.tenantId))
        $Partner.PSObject.Properties.Add([psnoteproperty]::new('partnerName', $Lookup.displayName))
        $Partner.PSObject.Properties.Add([psnoteproperty]::new('partnerDomain', $Lookup.defaultDomainName))
        $Partner
    }
}
