function Get-CippOffloadSuffix {
    <#
    .SYNOPSIS
        Returns the offload-app suffix for a function app name, or $null when it is not an
        offloaded app.

    .DESCRIPTION
        When function offloading is enabled, extra Function Apps are deployed alongside the
        main app and share its resources (Key Vault, etc.). They are named
        '<mainname>-<suffix>' - e.g. 'compaction-01-z2ir2-standards'.

        This is the SINGLE SOURCE OF TRUTH for the known offload suffixes so that vault-name
        derivation ([[Get-CippKeyVaultName]]) and offload detection stay in sync. Matching is
        anchored to the end and requires a whole '-<suffix>' segment, so a legitimate dashed
        main-app name (e.g. 'compaction-01-z2ir2', which contains dashes but is NOT offloaded)
        is never misdetected.

        Keep $OffloadSuffixes in sync with the deployment's offload app names.

    .PARAMETER SiteName
        Function app name to inspect. Defaults to $env:WEBSITE_SITE_NAME (the current app).

    .EXAMPLE
        Get-CippOffloadSuffix -SiteName 'compaction-01-z2ir2-standards'   # -> 'standards'

    .EXAMPLE
        Get-CippOffloadSuffix -SiteName 'compaction-01-z2ir2'             # -> $null
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SiteName = $env:WEBSITE_SITE_NAME
    )

    $OffloadSuffixes = @('proc', 'auditlog', 'standards', 'usertasks')

    if ([string]::IsNullOrWhiteSpace($SiteName)) { return $null }

    foreach ($Suffix in $OffloadSuffixes) {
        if ($SiteName -match "-$([regex]::Escape($Suffix))$") {
            return $Suffix
        }
    }

    return $null
}
