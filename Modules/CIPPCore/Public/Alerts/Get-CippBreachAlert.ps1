
function Get-CippBreachAlert {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $TenantFilter
    )
    try {
        $Search = New-BreachTenantSearch -TenantFilter $TenantFilter
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $Search
    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Could not get New Breaches for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
