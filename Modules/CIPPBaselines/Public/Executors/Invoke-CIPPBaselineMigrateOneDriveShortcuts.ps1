function Invoke-CIPPBaselineMigrateOneDriveShortcuts {
    <#
    .SYNOPSIS
        Executor for MigrateOneDriveShortcuts: resolves each user's Shortcuts folder, then hands the
        moves to GraphBulkSweep.
    .DESCRIPTION
        The move needs the destination folder id, which only a per-user special/shortcuts read
        returns - and that read belongs to the write, not the compare. Folder ids are resolved in
        one $batch, attached to the cached targets as folderId, and the definition's writes[] spec
        does the PATCHes. Users whose folder cannot be resolved are skipped with a warning; if none
        resolve, it throws.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Remediate, $TenantFilter, $Current)

    # The engine also writes when Current is null (create-if-missing); with no scan there is nothing to move.
    if (-not ($Current -and $Current.PSObject.Properties.Name -contains 'targets')) {
        throw 'MigrateOneDriveShortcuts: no cached OneDrive shortcut scan to remediate from.'
    }
    $Targets = @(@($Current.targets).Where({ $_.userId -and $_.itemId }))
    if ($Targets.Count -eq 0) { return }

    $UserIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Requests = foreach ($Target in $Targets) {
        if ($UserIds.Add($Target.userId)) { @{ id = $Target.userId; method = 'GET'; url = "users/$($Target.userId)/drive/special/shortcuts?`$select=id" } }
    }
    $FolderByUser = @{}
    $Failures = [System.Collections.Generic.List[string]]::new()
    foreach ($Response in @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($Requests) -asapp $true)) {
        if ([int]$Response.status -ge 200 -and [int]$Response.status -le 299 -and $Response.body.id) {
            $FolderByUser["$($Response.id)"] = "$($Response.body.id)"
        } else {
            $Failures.Add("$($Response.id) -> $($Response.status) $($Response.body.error.message)")
        }
    }
    if ($Failures.Count -gt 0) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "MigrateOneDriveShortcuts: could not resolve the Shortcuts folder for $($Failures.Count) of $($UserIds.Count) users. $($Failures.GetRange(0, [Math]::Min(10, $Failures.Count)) -join ' | ')" -Sev 'Warning'
    }

    $Resolved = foreach ($Target in $Targets) {
        $FolderId = $FolderByUser[$Target.userId]
        if ($FolderId) { [PSCustomObject]@{ userId = $Target.userId; itemId = $Target.itemId; folderId = $FolderId } }
    }
    if (@($Resolved).Count -eq 0) { throw "MigrateOneDriveShortcuts: no Shortcuts folder could be resolved. $($Failures[0])" }

    Invoke-CIPPBaselineGraphBulkSweep -Remediate $Remediate -TenantFilter $TenantFilter -Current ([PSCustomObject]@{ targets = @($Resolved) })
}
