function Get-CippPartnerTenantInfo {
    <#
    .SYNOPSIS
        Get the Microsoft Partner status of the CIPP host tenant
    .DESCRIPTION
        Reads the organization object of the CIPP host tenant and reports whether it is a
        Microsoft Partner tenant.

        The tenant is pinned to $env:TenantID here rather than taken from the caller, so the
        answer never depends on request input. That is what lets callers that need nothing but
        the partner flag be marked AnyTenant: the question is about the CIPP instance itself,
        not about a tenant the user is asking to act on.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $Org = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/organization?$select=displayName,partnerTenantType' -tenantid $env:TenantID -NoAuthCheck $true | Select-Object -First 1

    return [PSCustomObject]@{
        isPartnerTenant   = [bool]$Org.partnerTenantType
        partnerTenantType = $Org.partnerTenantType
        orgName           = $Org.displayName
    }
}
