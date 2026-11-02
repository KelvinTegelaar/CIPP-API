function Update-CIPPSAMCertificateEnvCache {
    <#
    .SYNOPSIS
    Refreshes the in-process SAM certificate caches after a store

    .DESCRIPTION
    Updates the preloaded environment variable and invalidates the script-scope certificate
    cache so the current runspace immediately serves the newly stored certificate. Other
    runspaces pick it up when their 1 hour memory cache expires or on restart; the previous
    certificate remains valid on the app registration during that window.

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$PfxBase64
    )

    if ($Name -eq 'SAMCertificate') {
        $env:SAMCertificate = $PfxBase64
    }
    if ($script:SAMCertificateCache) {
        $script:SAMCertificateCache.Remove($Name)
    }
}
