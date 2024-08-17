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
                $RogueApp = $RogueApps | Where-Object { $_.appId -eq $ServicePrincipal.appId }
                [pscustomobject]@{
                    appDisplayName  = $RogueApp.appDisplayName
                    appId           = $RogueApp.appId
                    description     = $RogueApp.description
                    accountEnabled  = $ServicePrincipal.accountEnabled
                    createdDateTime = $ServicePrincipal.createdDateTime
                    tags            = $RogueApp.tags -join ', '
                    references      = $RogueApp.references -join ', '
                    huntressAdded   = $RogueApp.dateAdded
                }
            }
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        #Write-AlertMessage -tenant $($TenantFilter) -message "Failed to check for rogue apps for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
