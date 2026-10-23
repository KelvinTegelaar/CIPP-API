function Get-CIPPRiskyPermissionCatalog {
    <#
    .SYNOPSIS
        Returns Config/RiskyPermissions.json with lookups for app role assignments and delegated grants.
    .DESCRIPTION
        Parsed once per worker and re-read when the file changes. Application entries are keyed on
        'api|id' and delegated entries on 'api|name': Exchange Online's legacy roles reuse Graph ids.
    #>
    [CmdletBinding()]
    param()

    $Path = Join-Path $env:CIPPRootPath 'Config/RiskyPermissions.json'
    $Stamp = [System.IO.File]::GetLastWriteTimeUtc($Path)
    $Cached = $script:CIPPRiskyPermissionCatalog
    if ($Cached -and $Cached.Path -eq $Path -and $Cached.Stamp -eq $Stamp) { return $Cached }

    $Entries = @([System.IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop)
    $Application = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Delegated = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Entry in $Entries) {
        if ($Entry.type -eq 'Application') {
            $Application["$($Entry.api)|$($Entry.id)"] = $Entry
        } elseif ($Entry.type -eq 'Delegated') {
            $Delegated["$($Entry.api)|$($Entry.name)"] = $Entry
        }
    }

    $script:CIPPRiskyPermissionCatalog = [PSCustomObject]@{
        Path        = $Path
        Stamp       = $Stamp
        Entries     = $Entries
        Application = $Application
        Delegated   = $Delegated
    }
    return $script:CIPPRiskyPermissionCatalog
}
