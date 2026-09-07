function Get-CIPPAppServiceSite {
    <#
    .SYNOPSIS
        Resolves the App Service hosting this CIPP instance and the certificates its plan can bind.
    .DESCRIPTION
        One ARM read of the site (Microsoft.Web/sites/$env:WEBSITE_SITE_NAME, via the managed
        identity) plus one of the certificates in the plan's resource group. A certificate binds
        from the App Service PLAN's webspace, not the site's, so when the plan lives in another
        resource group (a shared plan) certificates are created and looked up there. On a dedicated
        plan both resource groups are the same.

        The certificate list is best effort: an identity without rights on the plan's resource
        group gets an empty list, and the caller's create/bind then fails with the real 403.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        $AppService = Get-CIPPAppServiceSite
        $AppService.Site.properties.hostNames
    #>
    [CmdletBinding()]
    param(
        [string]$ApiVersion = '2024-11-01'
    )

    $SiteName = $env:WEBSITE_SITE_NAME
    $ResourceGroup = Get-CIPPFunctionAppResourceGroup -SiteName $SiteName
    $SubscriptionId = Get-CIPPAzFunctionAppSubId
    $ArmBase = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Web/sites/$SiteName"
    $Site = New-CIPPAzRestRequest -Uri "$ArmBase`?api-version=$ApiVersion" -Method GET -ErrorAction Stop

    $PlanId = [string]$Site.properties.serverFarmId
    $CertResourceGroup = if ($PlanId -match '(?i)/resourceGroups/([^/]+)/') { $Matches[1] } else { $ResourceGroup }
    $CertBase = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$CertResourceGroup/providers/Microsoft.Web/certificates"
    $Certificates = try {
        @((New-CIPPAzRestRequest -Uri "$CertBase`?api-version=$ApiVersion" -Method GET -ErrorAction Stop).value)
    } catch {
        Write-Information "Could not list certificates in resource group '$CertResourceGroup': $($_.Exception.Message)"
        @()
    }

    [pscustomobject]@{
        SubscriptionId    = $SubscriptionId
        SiteName          = $SiteName
        ResourceGroup     = $ResourceGroup
        CertResourceGroup = $CertResourceGroup
        ArmBase           = $ArmBase
        CertBase          = $CertBase
        ApiVersion        = $ApiVersion
        Site              = $Site
        Certificates      = $Certificates
    }
}
