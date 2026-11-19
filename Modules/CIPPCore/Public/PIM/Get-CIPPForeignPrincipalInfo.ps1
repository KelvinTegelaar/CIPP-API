function Get-CIPPForeignPrincipalInfo {
    <#
    .SYNOPSIS
        Classifies and names the role-assignment principals that live in another tenant.

    .DESCRIPTION
        A partner's GDAP group holds a directory role in the customer tenant but lives in the
        partner tenant, so it never resolves in the customer's directory. The assignment's
        principalOrganizationId names the owning tenant.

        Returns a hashtable principalId -> { TenantId, Type, Name } for every assignment whose
        principalOrganizationId differs from the tenant's own id:
          Type  'Partner (GDAP)' when the owner is a partner tenant CIPP runs as (it only reaches
                a customer's roles through GDAP), otherwise 'Foreign (likely GDAP)'.
          Name  the owning tenant's name, or 'Group (Tenant)' when the group is readable (own
                partner tenants only). Lookups are best effort; the tenant id is the fallback.

        Makes Graph calls, so it is for live reads and the cache writer, never a cache read.

    .PARAMETER Assignments
        unifiedRoleAssignment objects carrying principalId and principalOrganizationId.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        $Assignments
    )

    $Info = @{}
    # Without the home id nothing can be told apart: every principal of the tenant itself would
    # look foreign.
    $HomeTenantId = (Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1).customerId
    if (-not $HomeTenantId) { return $Info }

    $OrgByPrincipal = @{}
    foreach ($Item in @($Assignments)) {
        if ($Item.principalId -and $Item.principalOrganizationId -and $Item.principalOrganizationId -ne $HomeTenantId) {
            $OrgByPrincipal[$Item.principalId] = $Item.principalOrganizationId
        }
    }
    if ($OrgByPrincipal.Count -eq 0) { return $Info }
    $OrgIds = @($OrgByPrincipal.Values | Sort-Object -Unique)

    $OrgNames = @{}
    $OwnPartners = [System.Collections.Generic.List[string]]::new()
    if ($env:TenantID) { $OwnPartners.Add($env:TenantID) }
    foreach ($Partner in @(Get-CIPPPartnerTenantList)) {
        if (-not $Partner.partnerTenantId) { continue }
        $OwnPartners.Add($Partner.partnerTenantId)
        if ($Partner.displayName) { $OrgNames[$Partner.partnerTenantId] = $Partner.displayName }
    }

    # As the partner tenant, like the other tenant lookups: a failed batch sent as the customer
    # would mark that customer's tenant row with a Graph error.
    $OrgRequests = @(foreach ($OrgId in $OrgIds) {
            if (-not $OrgNames.ContainsKey($OrgId)) { @{ id = $OrgId; method = 'GET'; url = "/tenantRelationships/findTenantInformationByTenantId(tenantId='$OrgId')" } }
        })
    if ($OrgRequests.Count -gt 0) {
        try {
            foreach ($Response in @(New-GraphBulkRequest -tenantid $env:TenantID -NoAuthCheck $true -asapp $true -Requests $OrgRequests -Version 'v1.0')) {
                if ($Response.body.displayName) { $OrgNames[[string]$Response.id] = $Response.body.displayName }
            }
        } catch {
            Write-Information "Could not resolve foreign tenant names for $TenantFilter`: $($_.Exception.Message)"
        }
    }

    # The group itself is only readable in a partner tenant CIPP runs as; another partner's
    # groups stay at tenant level.
    $GroupNames = @{}
    foreach ($OrgId in @($OrgIds | Where-Object { $_ -in $OwnPartners })) {
        try {
            $Body = ConvertTo-Json -InputObject @{ ids = @($OrgByPrincipal.Keys | Where-Object { $OrgByPrincipal[$_] -eq $OrgId }) } -Compress
            $Resolved = New-GraphPOSTRequest -tenantid $OrgId -uri 'https://graph.microsoft.com/v1.0/directoryObjects/getByIds?$select=id,displayName' -body $Body -AsApp $true -NoAuthCheck $true
            foreach ($Group in @($Resolved.value)) { if ($Group.displayName) { $GroupNames[$Group.id] = $Group.displayName } }
        } catch {
            Write-Information "Could not resolve partner groups in $OrgId`: $($_.Exception.Message)"
        }
    }

    foreach ($PrincipalId in $OrgByPrincipal.Keys) {
        $OrgId = $OrgByPrincipal[$PrincipalId]
        $OrgName = $OrgNames[$OrgId] ?? $OrgId
        $Info[$PrincipalId] = [PSCustomObject]@{
            TenantId = $OrgId
            Type     = if ($OrgId -in $OwnPartners) { 'Partner (GDAP)' } else { 'Foreign (likely GDAP)' }
            Name     = if ($GroupNames[$PrincipalId]) { "$($GroupNames[$PrincipalId]) ($OrgName)" } else { $OrgName }
        }
    }
    return $Info
}
