function Test-CippOffloadFunctionApp {
    <#
    .SYNOPSIS
        Returns $true when the given (or current) function app is an offloaded app.

    .DESCRIPTION
        Thin boolean wrapper over [[Get-CippOffloadSuffix]] for readability at detection sites.
        An app is "offloaded" when its name ends with a known offload suffix (e.g. '-standards').
        A dashed main-app name (e.g. 'compaction-01-z2ir2') is NOT offloaded.

    .PARAMETER SiteName
        Function app name to inspect. Defaults to $env:WEBSITE_SITE_NAME (the current app).

    .EXAMPLE
        Test-CippOffloadFunctionApp -SiteName 'compaction-01-z2ir2-proc'   # -> $true
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SiteName = $env:WEBSITE_SITE_NAME
    )

    return [bool](Get-CippOffloadSuffix -SiteName $SiteName)
}
