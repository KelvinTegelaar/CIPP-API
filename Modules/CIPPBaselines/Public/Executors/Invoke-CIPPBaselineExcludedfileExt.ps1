function Invoke-CIPPBaselineExcludedfileExt {
    <#
    .SYNOPSIS
        ExcludedfileExt executor: writes the OneDrive sync exclusion list.
    .DESCRIPTION
        One PATCH with the full normalized list, app-only, replacing the tenant list - the
        admin center's own semantics and the classic's write.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Exts = @(("$($Remediate.ext)" -replace ' ', '') -split ',' | Where-Object { $_ } | ForEach-Object {
            if ($_ -notlike '*.*') { "*.$_" } else { $_ }
        } | Sort-Object -Unique)
    if ($Exts.Count -eq 0) { return }

    $Body = ConvertTo-Json -InputObject @{ excludedFileExtensionsForSyncApp = @($Exts) }
    $null = New-GraphPostRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -type PATCH -body $Body -AsApp $true -ContentType 'application/json'
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Set $($Exts.Count) excluded sync extensions." -Sev 'Info'
}
