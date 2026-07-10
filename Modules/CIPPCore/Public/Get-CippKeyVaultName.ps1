function Get-CippKeyVaultName {
    <#
    .SYNOPSIS
        Returns the name of the CIPP Azure Key Vault for the current instance.

    .DESCRIPTION
        The Key Vault is named after the main App Service instance, so its name equals
        $env:WEBSITE_SITE_NAME on the main app.

        Two things have to be handled:

        1. Dashed instance names. Earlier code derived the vault name as
           ($env:WEBSITE_DEPLOYMENT_ID -split '-')[0], which keeps only the segment before
           the first dash. That silently truncated any instance name containing a dash -
           e.g. 'compaction-01-z2ir2' became 'compaction' - so every secret call was pointed
           at a vault that does not exist (404). The full name must be kept intact.

        2. Offloaded function apps. When function offloading is enabled, extra Function Apps
           are deployed alongside the main app and share its Key Vault. They are named
           '<mainname>-<suffix>' (e.g. 'compaction-01-z2ir2-standards'). Those apps must
           resolve the SAME vault as the main app, so a known offload suffix is stripped from
           the end of the site name. Only the fixed offload suffixes are stripped, never an
           arbitrary trailing segment, so a legitimate dashed vault name is left intact.

        This is the single source of truth for the vault name so those bugs cannot reappear
        per call site.

    .EXAMPLE
        $VaultName = Get-CippKeyVaultName
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Primary: the App Service site name IS the vault name (on the main app).
    # Fallback: the full deployment id. Never split on '-' (that is the truncation bug this
    # helper exists to prevent); a dashed vault name must be kept whole.
    $Name = if (-not [string]::IsNullOrWhiteSpace($env:WEBSITE_SITE_NAME)) {
        $env:WEBSITE_SITE_NAME
    } elseif (-not [string]::IsNullOrWhiteSpace($env:WEBSITE_DEPLOYMENT_ID)) {
        $env:WEBSITE_DEPLOYMENT_ID
    } else {
        return $null
    }

    # If running on an offloaded app ('<mainname>-<suffix>'), strip the known suffix so it
    # resolves the SAME vault as the main app. Get-CippOffloadSuffix is the single source of
    # truth for the suffix list.
    $Suffix = Get-CippOffloadSuffix -SiteName $Name
    if ($Suffix) {
        $Name = $Name -replace "-$([regex]::Escape($Suffix))$", ''
    }

    return $Name
}
