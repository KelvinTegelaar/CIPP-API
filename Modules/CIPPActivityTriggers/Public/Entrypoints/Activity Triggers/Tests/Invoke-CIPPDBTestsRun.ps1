function Invoke-CIPPDBTestsRun {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Tests.Read
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter = 'allTenants',

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    return Start-CIPPDBTestsRun -TenantFilter $TenantFilter -Force:$Force
}
