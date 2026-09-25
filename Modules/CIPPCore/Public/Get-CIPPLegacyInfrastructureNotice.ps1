function Get-CIPPLegacyInfrastructureNotice {
    <#
    .SYNOPSIS
    Build the legacy infrastructure warning for instances still running on Azure Function Apps.

    .DESCRIPTION
    CIPP now ships as a single Linux container Web App. Instances that are still on the original
    Function App and Static Web App deployment are on legacy infrastructure that will stop receiving
    updates. This returns a warning shaped as a GetCippAlerts maintenance alert so the frontend
    renders it in the same full-width banner as a hosted maintenance notice, or $null when the
    instance is already on the new infrastructure (CIPPNG) or is running locally   This runs on every page load for every user, so it never throws and never touches Graph or table
    storage.

    .EXAMPLE
    Get-CIPPLegacyInfrastructureNotice
    #>
    [CmdletBinding()]
    param()
    if ($env:CIPPNG -eq 'true' -or $env:CIPP_HOSTED -eq 'true') { return $null }
    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') { return $null }
    $Message = 'This CIPP instance is running on the legacy Function App infrastructure, which will soon stop receiving updates. Migrate to the new infrastructure to keep receiving new features and fixes. The migration keeps your storage account and Key Vault, so your configuration carries across.'

    return @{
        title       = 'Legacy infrastructure'
        Alert       = $Message
        link        = 'https://docs.cipp.app/setup/maintaining-cipp/migrating-to-the-new-infrastructure'
        linkText    = 'Migration guide'
        type        = 'warning'
        maintenance = $true
        noticeId    = 'legacy-function-app-infrastructure'
        startTime   = $null
        endTime     = $null
        active      = $false
        dismissible = $false
    }
}
