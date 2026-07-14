function Push-StoreOneDriveRootPermissions {
    <#
    .SYNOPSIS
        Post-execution function that aggregates per-batch OneDrive root permission rows and writes the cache.

    .DESCRIPTION
        Collects the Sites arrays returned by every Push-DBCacheOneDriveRootPermissionsBatch activity,
        flattens them into a single row set, and writes OneDriveRootPermissions once via Add-CIPPDbItem.

        Completeness guard: if ActualCount -ne ExpectedSiteCount the function throws and does not
        call Add-CIPPDbItem (prevents replace-mode wipe on partial orchestrator failure). When counts
        match (including 0 for empty tenants handled by the orchestrator parent), a single full-replace
        write is performed.

        Merge-on-Skip: when batch collection returns Skipped for a site, loads existing
        OneDriveRootPermissions via New-CIPPDbRequest and replaces the Skipped row with the prior
        Full row (matched by siteId) before writing. Transient SPO/Graph failures therefore do not
        wipe previously collected grant data. Skipped rows with no prior Full row are written as-is.
        DB read is skipped when no Skipped rows exist in the run.

        Logs Skipped count from collection and how many were preserved from prior Full cache.

        Cache row schema (one per personal site):
        id/siteId, siteUrl, siteDisplayName, ownerPrincipalName, ownerObjectId, ownerDisplayName,
        driveId, driveWebUrl, libraryId, libraryHasUniquePermissions, collectionStatus,
        collectionError, hasNonStandardAccess (nullable boolean), permissionsJson (string),
        grantCount, collectedAt.

        permissionsJson is a pre-serialized JSON string of grant objects — consumers must
        ConvertFrom-Json before querying grants. Grant identity for dedup:
        {permissionSource}_{principalId}_{roleDefinitionId}_{permissionId}

        Consumer notes:
        - Rows in the cache reflect merge-on-Skip: a site that failed collection this run may still
          show collectionStatus Full with prior permissionsJson if a previous Full row existed
        - hasNonStandardAccess: use -eq $true / -eq $false; $null means Skipped with no prior Full
          row to merge. Never use truthy checks
        - DriveRootLink with named recipients produces one grant per person; count sharing links
          by distinct permissionId within permissionsJson, not by grant row count (same permissionId
          may appear on multiple recipient grants)

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.Parameters.TenantFilter
    $ExpectedSiteCount = [int]$Item.Parameters.ExpectedSiteCount

    try {
        $AllRows = [System.Collections.Generic.List[object]]::new()
        foreach ($BatchResult in @($Item.Results)) {
            $Sites = if ($BatchResult.Sites) { @($BatchResult.Sites) } else { @() }
            foreach ($Row in $Sites) {
                if ($Row) { $AllRows.Add($Row) }
            }
        }

        $ActualCount = $AllRows.Count
        if ($ActualCount -ne $ExpectedSiteCount) {
            throw "OneDrive root permissions completeness check failed for $TenantFilter : expected $ExpectedSiteCount site rows, got $ActualCount"
        }

        $SkippedCount = @($AllRows | Where-Object { $_.collectionStatus -eq 'Skipped' }).Count
        $MergedCount = 0
        if ($SkippedCount -gt 0) {
            $ExistingBySiteId = @{}
            foreach ($Existing in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'OneDriveRootPermissions')) {
                $Key = [string]($Existing.siteId ?? $Existing.id)
                if ($Key -and $Existing.collectionStatus -eq 'Full') {
                    $ExistingBySiteId[$Key] = $Existing
                }
            }
            for ($i = 0; $i -lt $AllRows.Count; $i++) {
                $Row = $AllRows[$i]
                if ($Row.collectionStatus -ne 'Skipped') { continue }
                $Key = [string]($Row.siteId ?? $Row.id)
                if ($Key -and $ExistingBySiteId.ContainsKey($Key)) {
                    $AllRows[$i] = $ExistingBySiteId[$Key]
                    $MergedCount++
                }
            }
        }

        $RemainingSkippedCount = $SkippedCount - $MergedCount
        if ($SkippedCount -gt 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive root permissions: $SkippedCount of $ActualCount sites returned Skipped from collection; preserved $MergedCount from prior Full cache; $RemainingSkippedCount written as Skipped" -sev Warning
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'OneDriveRootPermissions' -Data @($AllRows) -AddCount
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $ActualCount OneDrive root permission site rows ($MergedCount merge-on-Skip) across $(@($Item.Results).Count) batches" -sev Info
        return

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to store OneDrive root permissions: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
