function Get-CIPPSiteHostname {
    <#
    .SYNOPSIS
        Returns every hostname bound to the App Service running this instance.
    .DESCRIPTION
        Queries ARM for the site's properties.hostNames, which covers the default
        *.azurewebsites.net hostname plus every custom domain bound to it.

        A container can carry many custom domains, and EasyAuth builds its redirect_uri from
        the incoming Host header — so every bound hostname needs its own callback on the SSO
        app registration. Anything that writes redirectUris should source them from here
        rather than from a single "current" URL.

        When ARM cannot be reached (no managed identity, missing WEBSITE_* variables, a 403
        or a transient failure) the list falls back to WEBSITE_HOSTNAME plus the last known
        instance URL from Get-CIPPHostname. That fallback is NOT complete — a custom domain
        nobody has browsed yet will be absent — so callers must not treat "nothing missing"
        as proof that every domain can sign in. Use -IncludeStatus to tell the two apart.

        In local development the fallback is skipped entirely and the list comes back empty,
        so callers no-op rather than writing a localhost callback to a real app registration.
    .PARAMETER AsRedirectUri
        Return the EasyAuth callback URI for each hostname instead of the bare hostname.
    .PARAMETER IncludeStatus
        Return an object with Hostnames, RedirectUris, Discovered and Error instead of a bare
        list, so the caller can distinguish an authoritative list from a best-effort fallback.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [switch]$AsRedirectUri,
        [switch]$IncludeStatus
    )

    $Discovered = $false
    $DiscoveryError = $null
    $Hostnames = [System.Collections.Generic.List[string]]::new()
    $IsLocalDev = $env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true'

    try {
        $SiteName = $env:WEBSITE_SITE_NAME
        $ResourceGroup = $env:WEBSITE_RESOURCE_GROUP
        $SubscriptionId = if ($env:WEBSITE_OWNER_NAME) { ($env:WEBSITE_OWNER_NAME -split '\+')[0] } else { $null }

        if (-not ($SiteName -and $ResourceGroup -and $SubscriptionId)) {
            throw 'Not running in App Service (WEBSITE_SITE_NAME/WEBSITE_RESOURCE_GROUP/WEBSITE_OWNER_NAME not set).'
        }
        if (-not ($env:IDENTITY_ENDPOINT -and $env:IDENTITY_HEADER)) {
            throw 'No managed identity is available to query ARM.'
        }

        $SiteUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Web/sites/$SiteName`?api-version=2024-11-01"
        $SiteResponse = New-CIPPAzRestRequest -Uri $SiteUri -Method GET -ErrorAction Stop

        if (-not $SiteResponse.properties.hostNames) {
            throw 'ARM returned no hostNames for this site.'
        }

        $SiteResponse.properties.hostNames | ForEach-Object { $Hostnames.Add($_) }
        $Discovered = $true
        Write-Information "[SiteHostname] Discovered hostnames from ARM: $($Hostnames -join ', ')"
    } catch {
        $DiscoveryError = $_.Exception.Message
        Write-Information "[SiteHostname] ARM hostname discovery failed — falling back to known hostnames: $DiscoveryError"
    }

    if (-not $Discovered) {
        # Best effort: the platform hostname, plus the last URL the instance was actually
        # served from (Config/InstanceProperties/CIPPURL), which is usually the custom domain.
        if ($env:WEBSITE_HOSTNAME) { $Hostnames.Add($env:WEBSITE_HOSTNAME) }

        # ...but NOT in local dev. There is no App Service there, so discovery always fails and
        # we would fall through to the stored CIPPURL - which Invoke-ExecPartnerWebhook -Save
        # writes from the request host, i.e. 'localhost'. The dev SSO AppId in DevSecrets points
        # at a REAL app registration, so that would permanently graft a localhost callback onto
        # it. Returning nothing here makes the callers no-op, which is what dev should do.
        if ($IsLocalDev) {
            Write-Information '[SiteHostname] Local development - skipping stored instance URL fallback'
        } else {
            try {
                $KnownHost = Get-CIPPHostname
                if (-not [string]::IsNullOrWhiteSpace($KnownHost) -and $KnownHost -notin $Hostnames) {
                    $Hostnames.Add($KnownHost)
                }
            } catch {
                Write-Information "[SiteHostname] Stored instance URL lookup failed: $($_.Exception.Message)"
            }
        }

        # Belt and braces: a loopback or unqualified name is never a hostname EasyAuth serves,
        # and registering one on the app registration would be junk that nothing cleans up.
        $Local = @($Hostnames | Where-Object { $_ -in @('localhost', '127.0.0.1', '::1') -or $_ -notlike '*.*' })
        foreach ($Bad in $Local) {
            Write-Information "[SiteHostname] Ignoring non-routable hostname '$Bad'"
            $null = $Hostnames.Remove($Bad)
        }
    }

    $RedirectUris = @($Hostnames | ForEach-Object { "https://$_/.auth/login/aad/callback" })

    if ($IncludeStatus) {
        return [PSCustomObject]@{
            Hostnames    = @($Hostnames)
            RedirectUris = $RedirectUris
            Discovered   = $Discovered
            Error        = $DiscoveryError
        }
    }
    if ($AsRedirectUri) {
        return $RedirectUris
    }
    return @($Hostnames)
}
