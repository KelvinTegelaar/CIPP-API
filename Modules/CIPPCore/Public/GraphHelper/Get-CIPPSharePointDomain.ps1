function Get-CIPPSharePointDomain {
    <#
    .SYNOPSIS
        Maps a tenant's initial (onmicrosoft) domain to the SharePoint domain that goes with it.
    .DESCRIPTION
        SharePoint is only on sharepoint.com in the commercial cloud. Sovereign clouds keep their
        own domain, and the tenant's initial domain carries the same TLD:

            contoso.onmicrosoft.de        -> sharepoint.de   (old German tenants, see issue #269)
            contoso.partner.onmschina.cn  -> sharepoint.cn   (21Vianet)
            contoso.onmicrosoft.us        -> sharepoint.us   (GCC High)
            contoso.onmicrosoft.com       -> sharepoint.com

        This is a best-effort mapping for the paths that cannot ask Graph (autodiscover, cached
        values, extension fallbacks). Prefer Get-SharePointAdminLink, which reads the real host off
        the tenant's root site - it is the only way to tell DoD (sharepoint-mil.us) from GCC High,
        since both are onmicrosoft.us.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        # The tenant's initial domain, e.g. contoso.onmicrosoft.de
        [string]$TenantDomain
    )

    switch -Regex ($TenantDomain) {
        '\.onmschina\.cn$' { return 'sharepoint.cn' }
        '\.onmicrosoft\.(?<Tld>[a-z]{2,})$' { return "sharepoint.$($Matches.Tld)" }
        default { return 'sharepoint.com' }
    }
}
