function Test-CIPPSharePointLibraryCopyEligible {
    <#
    .SYNOPSIS
        Returns whether a document library is eligible as source or destination for library copy.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Template,

        [string]$Title,
        [string]$Name
    )

    if ($Template -ne 'documentLibrary') {
        return [PSCustomObject]@{ Eligible = $false; Reason = 'Not a document library.' }
    }

    $TitleNorm = ([string]$Title).Trim()
    $NameNorm = ([string]$Name).Trim()

    $DeniedTitles = @(
        'Form Templates'
        'Style Library'
        'Preservation Hold Library'
        'Site Assets'
        'Site Pages'
    )
    foreach ($Denied in $DeniedTitles) {
        if ($TitleNorm -eq $Denied) {
            return [PSCustomObject]@{ Eligible = $false; Reason = "System library '$Denied' is not eligible." }
        }
    }

    if ($NameNorm -eq 'SiteAssets') {
        return [PSCustomObject]@{ Eligible = $false; Reason = 'Site Assets library is not eligible.' }
    }

    return [PSCustomObject]@{ Eligible = $true; Reason = $null }
}
