function Invoke-ExecBulkRemoveSharingLinks {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .DESCRIPTION
        Revokes all sharing links / external direct grants on one site in bulk, sourced from
        the SharePointSharingLinks reporting cache. Scope selects which classifications are
        revoked: Anonymous (anyone links only), External (anonymous + external), or All
        (every cached link on the site, including internal). Because the source is the
        reporting cache, links created after the last sharing sync are not covered.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $SiteUrl = $Request.Body.SiteUrl
    $Scope = $Request.Body.Scope.value ?? $Request.Body.Scope ?? 'Anonymous'

    $ScopeClassifications = @{
        'Anonymous' = @('Anonymous')
        'External'  = @('Anonymous', 'External')
        'All'       = @('Anonymous', 'External', 'Internal')
    }

    try {
        if (-not $SiteUrl) { throw 'SiteUrl is required.' }
        if (-not $ScopeClassifications.ContainsKey([string]$Scope)) {
            throw "Invalid scope '$Scope'. Valid values: $($ScopeClassifications.Keys -join ', ')."
        }
        $Classifications = $ScopeClassifications[[string]$Scope]

        try {
            $AllLinks = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'SharePointSharingLinks')
        } catch {
            throw "Could not read the sharing links cache: $($_.Exception.Message). Run a sharing report sync first."
        }
        $NormalizedSite = $SiteUrl.TrimEnd('/')
        $Targets = @($AllLinks | Where-Object {
                "$($_.siteUrl)".TrimEnd('/') -eq $NormalizedSite -and $_.classification -in $Classifications -and $_.driveId -and $_.itemId -and $_.permissionId
            })

        if ($Targets.Count -eq 0) {
            $Results = "No cached $($Scope -eq 'All' ? '' : "$Scope ")sharing links found for $SiteUrl. Links created since the last sharing sync are not in the cache - run a sync from the Sharing Report page to refresh."
            Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @{ 'Results' = $Results }
                })
        }

        $Revoked = [System.Collections.Generic.List[string]]::new()
        $Failed = [System.Collections.Generic.List[string]]::new()

        # Batch the DELETEs through Graph $batch (New-GraphBulkRequest, ~20 per request) instead of
        # one sequential call per link - a heavily-shared site can have hundreds/thousands.
        $BulkRequests = @(for ($i = 0; $i -lt $Targets.Count; $i++) {
                $Link = $Targets[$i]
                @{
                    id     = "$i"
                    method = 'DELETE'
                    url    = "drives/$($Link.driveId)/items/$($Link.itemId)/permissions/$($Link.permissionId)"
                }
            })
        $Responses = @(New-GraphBulkRequest -tenantid $TenantFilter -Requests $BulkRequests -asapp $true -Version 'v1.0')

        foreach ($Response in $Responses) {
            $Link = $Targets[[int]$Response.id]
            $Status = [int]$Response.status
            # 2xx = revoked; 404 = the link was already gone (treat as revoked). Either way, clean
            # the reporting cache row so it does not linger.
            if (($Status -ge 200 -and $Status -lt 300) -or $Status -eq 404) {
                $Revoked.Add($(if ($Status -eq 404) { "$($Link.fileName) (already removed)" } else { "$($Link.fileName) ($($Link.classification))" }))
                if ($Link.id) {
                    try { Remove-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointSharingLinks' -ItemId $Link.id } catch {
                        Write-Information "Revoked link but could not update reporting cache row $($Link.id): $($_.Exception.Message)"
                    }
                }
            } else {
                $Failed.Add("$($Link.fileName): $($Response.body.error.message ?? "status $Status")")
            }
        }

        $Messages = [System.Collections.Generic.List[string]]::new()
        $Messages.Add("Revoked $($Revoked.Count) of $($Targets.Count) $Scope sharing link(s) on $SiteUrl.")
        if ($Failed.Count -gt 0) {
            $Messages.Add("Failed: $($Failed -join '; ')")
        }
        $Messages.Add('Note: links created since the last sharing report sync are not covered.')
        $Results = $Messages -join ' '
        if ($Revoked.Count -eq 0 -and $Failed.Count -gt 0) {
            throw $Results
        }
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to bulk revoke sharing links on $($SiteUrl): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })
}
