function Get-CIPPLegacyInfrastructureNotice {
    <#
    .SYNOPSIS
    Build the legacy infrastructure warning for instances still running on Azure Function Apps.

    .DESCRIPTION
    CIPP now ships as a single Linux container Web App. Instances that are still on the original
    Function App and Static Web App deployment are on legacy infrastructure that will stop receiving
    updates. This returns a warning shaped as a GetCippAlerts maintenance alert so the frontend
    renders it in the same full-width banner as a hosted maintenance notice and raises a blocking
    migration dialog, or $null when the
    instance is already on the new infrastructure (CIPPNG) or is running locally   This runs on every page load for every user, so it never throws and never touches Graph or table
    storage.

    .EXAMPLE
    Get-CIPPLegacyInfrastructureNotice
    #>
    [CmdletBinding()]
    param()
    # CIPP_LEGACY_NOTICE_PREVIEW=true shows the notice regardless of where the instance runs, so the
    # banner and dialog can be exercised on local dev and on the new infrastructure.
    if ($env:CIPP_LEGACY_NOTICE_PREVIEW -ne 'true') {
        if ($env:CIPPNG -eq 'true' -or $env:CIPP_HOSTED -eq 'true') { return $null }
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') { return $null }
    }
    $Message = 'This CIPP instance is running on the legacy Function App infrastructure, which no longer receives updates starting December 2026. The new infrastructure is a single container that is faster, more reliable, cheaper to run and keeps itself up to date automatically. Migrate now to keep receiving new features and fixes. The migration keeps your storage account and Key Vault, so your configuration carries across.'

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
        prominent   = $true
        blocking    = $true
        cutoff      = '2026-12-01T00:00:00Z'
    }
}
