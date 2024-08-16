function Get-CIPPAlertHuntressRogueApps {
    <#
    .SYNOPSIS
        Check for rogue apps in a Tenant
    .DESCRIPTION
        This function checks for rogue apps in the tenant by comparing the service principals in the tenant with a list of known rogue apps provided by Huntress.
    .FUNCTIONALITY
        Entrypoint
    .LINK
        https://huntresslabs.github.io/rogueapps/
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        $RogueApps = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/huntresslabs/rogueapps/main/public/rogueapps.json'
        $RogueAppFilter = $RogueApps.appId -join "','"
        $ServicePrincipals = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$filter=appId in ('$RogueAppFilter')" -tenantid $TenantFilter

        if (($ServicePrincipals | Measure-Object).Count -gt 0) {
            $AlertData = foreach ($ServicePrincipal in $ServicePrincipals) {
                $RogueApps | Where-Object { $_.appId -eq $ServicePrincipal.appId }
            }
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        #Write-AlertMessage -tenant $($TenantFilter) -message "Failed to check for rogue apps for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
