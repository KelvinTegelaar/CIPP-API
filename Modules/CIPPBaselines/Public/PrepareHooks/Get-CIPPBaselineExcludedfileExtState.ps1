function Get-CIPPBaselineExcludedfileExtState {
    <#
    .SYNOPSIS
        Prepare hook for ExcludedfileExt: the OneDrive sync app's excluded file extensions.
    .DESCRIPTION
        Grades the excluded-extension SET exactly - the classic's remediation rewrote the
        whole list (its count check made partial matches drift too), so extensions removed
        from the baseline come OFF the tenant on remediation, matching the admin center's
        replace semantics. Extensions normalize the way the admin center normalizes them: a
        bare extension gains the *. prefix.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Settings = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'SharePointAdminSettings') | Select-Object -First 1
    if (-not $Settings) { return @{ Current = $null } }

    $Exts = @(("$($Item.Variables.ext)" -replace ' ', '') -split ',' | Where-Object { $_ } | ForEach-Object {
            if ($_ -notlike '*.*') { "*.$_" } else { $_ }
        } | Sort-Object -Unique)
    if ($Exts.Count -eq 0) { return @{ Current = $null } }

    @{
        Expected = [PSCustomObject]@{ excludedExtensions = @($Exts) }
        # No -Unique on the tenant side: the classic's count check made duplicates drift too.
        Current  = [PSCustomObject]@{ excludedExtensions = @($Settings.excludedFileExtensionsForSyncApp | Sort-Object) }
    }
}
