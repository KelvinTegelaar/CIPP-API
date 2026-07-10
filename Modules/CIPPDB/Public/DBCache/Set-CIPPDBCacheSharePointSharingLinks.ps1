function Set-CIPPDBCacheSharePointSharingLinks {
    <#
    .SYNOPSIS
        Fans out SharePoint & OneDrive sharing link collection, one activity per site.

    .DESCRIPTION
        Enumerates every site in the tenant (SharePoint sites and OneDrive personal sites) and the
        tenant's verified domains, then starts a child orchestration with one activity per site
        (Push-DBCacheSharePointSiteSharingLinks). Each site activity scans its own drives for shared
        items and returns the sharing-link rows; a single PostExecution
        (Push-StoreSharePointSharingLinks) aggregates all sites and writes the SharePointSharingLinks
        cache once. Scanning all sites inline in one activity buffers the whole tenant's file tree and
        OOM-kills the worker on large tenants - per-site fan-out bounds memory and runtime per activity.

    .PARAMETER TenantFilter
        The tenant to cache sharing links for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Starting SharePoint/OneDrive sharing link collection (per-site fan-out)' -sev Debug

        # Verified domains, used by each site activity to tell internal from external recipients.
        $InternalDomains = [System.Collections.Generic.List[string]]::new()
        try {
            $Domains = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/domains?`$select=id,isVerified" -tenantid $TenantFilter -asapp $true
            foreach ($Domain in ($Domains | Where-Object { $_.isVerified })) { $InternalDomains.Add([string]$Domain.id) }
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Could not list verified domains for sharing link classification: $($_.Exception.Message)" -sev Warning
        }

        # All sites, including OneDrive personal sites. Cheap - just the site list, no drive scan here.
        $Sites = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/getAllSites?`$select=id,displayName,name,webUrl,isPersonalSite&`$top=999" -tenantid $TenantFilter -asapp $true)

        if ($Sites.Count -eq 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No sites found; writing empty SharePointSharingLinks cache' -sev Debug
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointSharingLinks' -Data @() -AddCount
            return
        }

        $Batch = foreach ($Site in $Sites) {
            [PSCustomObject]@{
                FunctionName    = 'DBCacheSharePointSiteSharingLinks'
                TenantFilter    = $TenantFilter
                SiteId          = $Site.id
                SiteName        = $Site.displayName ?? $Site.name
                SiteUrl         = $Site.webUrl
                IsPersonalSite  = [bool]$Site.isPersonalSite
                InternalDomains = @($InternalDomains)
                QueueId         = $QueueId
                QueueName       = "Sharing Links - $($Site.webUrl)"
            }
        }

        # Track the per-site activities against the same queue counter.
        if ($QueueId) {
            try {
                Update-CippQueueEntry -RowKey $QueueId -TotalTasks $Sites.Count -IncrementTotalTasks
            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Could not update queue $QueueId with sharing-link tasks: $($_.Exception.Message)" -sev Warning
            }
        }

        $InputObject = [PSCustomObject]@{
            Batch            = @($Batch)
            OrchestratorName = "SharePointSharingLinks_$TenantFilter"
            SkipLog          = $true
            PostExecution    = @{
                FunctionName = 'StoreSharePointSharingLinks'
                Parameters   = @{
                    TenantFilter = $TenantFilter
                }
            }
        }

        $null = Start-CIPPOrchestrator -InputObject $InputObject
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Started sharing link collection across $($Sites.Count) sites" -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to start SharePoint sharing link collection: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
