function Get-CIPPFunctionAppResourceGroup {
    <#
    .SYNOPSIS
        Resolve the resource group that the CIPP Function App site lives in.
    .DESCRIPTION
        Returns the resource group of the running Function App, using authoritative sources only:

            1. WEBSITE_RESOURCE_GROUP - platform-injected, the site's actual RG. Free, no decode.
            2. xms_mirid claim from the managed identity token - the site's own ARM resource ID,
               present even when WEBSITE_RESOURCE_GROUP is empty, needs no extra call or permission.

        The legacy approach of parsing WEBSITE_OWNER_NAME is intentionally NOT used: that string
        encodes the App Service Plan's webspace RG, which is frequently different from the site's RG
        (e.g. it returns 'DefaultResourceGroup-WEU' or '<rg>-m01' for sites whose plan was created
        in an auto-generated/other resource group). Writing auth settings, restarting, or querying
        the wrong RG is worse than failing, so this throws when no reliable source is available.
    .PARAMETER SiteName
        The Function App site name to resolve. Defaults to WEBSITE_SITE_NAME.
    .EXAMPLE
        Get-CIPPFunctionAppResourceGroup
        Returns e.g. 'CIPP-myinstance'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$SiteName = $env:WEBSITE_SITE_NAME
    )

    # 1. Platform-injected site resource group - authoritative, zero cost.
    if ($env:WEBSITE_RESOURCE_GROUP) {
        return $env:WEBSITE_RESOURCE_GROUP
    }

    # 2. The managed identity's own token names this site's resource ID (incl. RG). Only trust it
    #    when it actually points at this Microsoft.Web/sites resource, so a user-assigned identity
    #    (whose xms_mirid is a userAssignedIdentities resource) falls through rather than returning
    #    the identity's RG.
    try {
        $MiRid = Get-CIPPManagedIdentityResourceId
        if ($SiteName -and $MiRid -match "(?i)/resourcegroups/(?<RG>[^/]+)/providers/Microsoft\.Web/sites/$([regex]::Escape($SiteName))(/|$)") {
            return $Matches.RG
        }
        Write-Information "xms_mirid did not match site '$SiteName': $MiRid"
    } catch {
        Write-Warning "Could not read resource group from managed identity token: $($_.Exception.Message)"
    }

    # 3. No reliable source - fail loudly rather than guess from WEBSITE_OWNER_NAME.
    throw "Could not determine the function app resource group for site '$SiteName'. WEBSITE_RESOURCE_GROUP is empty and the managed identity resource ID was unavailable."
}
