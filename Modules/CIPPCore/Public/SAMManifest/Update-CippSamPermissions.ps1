function Update-CippSamPermissions {
    <#
    .SYNOPSIS
        Reconciles the saved CIPP-SAM additional-permission set in the AppPermissions table.
    .DESCRIPTION
        The SAM manifest is the immutable permission base and is always layered in at read time by
        Get-CippSamPermissions, so the AppPermissions table only ever needs to hold the EXTRA
        permissions an admin layered on top. This function keeps that row clean: it drops any saved
        entries the manifest now covers (e.g. legacy rows that stored the full manifest+extras set)
        so the table stays "extras only".

        It deliberately does NOT write the partner CIPP-SAM app registration's requiredResourceAccess.
        Permissions reach the CIPP-SAM service principal(s) - partner and clients - through the grant
        flow (Add-CIPPApplicationPermission / Add-CIPPDelegatedPermission, which read this table), not
        through the app registration. Refreshing those grants is handled by the caller
        (Invoke-ExecPermissionRepair for the partner, the per-tenant permission refresh for clients).
    .PARAMETER UpdatedBy
        The user or system that is performing the update. Defaults to 'CIPP-API'.
    .OUTPUTS
        String indicating the result of the operation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$UpdatedBy = 'CIPP-API'
    )

    try {
        # Manifest base - always-required permissions that are layered in at read time, so they never
        # need to live in the saved extras row.
        $ManifestPermissions = (Get-CippSamPermissions -ManifestOnly).Permissions

        $Table = Get-CIPPTable -TableName 'AppPermissions'
        $SavedRow = Get-CippAzDataTableEntity @Table -Filter "PartitionKey eq 'CIPP-SAM' and RowKey eq 'CIPP-SAM'"
        if (-not $SavedRow.Permissions) {
            return 'No additional permissions saved. CIPP default (manifest) permissions are always applied.'
        }

        try {
            $Saved = $SavedRow.Permissions | ConvertFrom-Json -ErrorAction Stop
        } catch {
            return 'Saved additional permissions could not be parsed; nothing to reconcile.'
        }

        # Keep only the entries the manifest does NOT already cover.
        $Extras = @{}
        $RemovedCount = 0
        foreach ($AppId in $Saved.PSObject.Properties.Name) {
            $ManifestApp = $ManifestPermissions.$AppId
            $ManifestAppIds = @($ManifestApp.applicationPermissions.id)
            $ManifestDelIds = @($ManifestApp.delegatedPermissions.id)

            $ExtraApp = [System.Collections.Generic.List[object]]::new()
            foreach ($Permission in $Saved.$AppId.applicationPermissions) {
                if ($Permission.id -and $ManifestAppIds -notcontains $Permission.id) {
                    $ExtraApp.Add([PSCustomObject]@{ id = $Permission.id; value = $Permission.value })
                } else {
                    $RemovedCount++
                }
            }
            $ExtraDel = [System.Collections.Generic.List[object]]::new()
            foreach ($Permission in $Saved.$AppId.delegatedPermissions) {
                if ($Permission.id -and $ManifestDelIds -notcontains $Permission.id) {
                    $ExtraDel.Add([PSCustomObject]@{ id = $Permission.id; value = $Permission.value })
                } else {
                    $RemovedCount++
                }
            }

            if ($ExtraApp.Count -gt 0 -or $ExtraDel.Count -gt 0) {
                $Extras.$AppId = @{
                    applicationPermissions = @($ExtraApp)
                    delegatedPermissions   = @($ExtraDel)
                }
            }
        }

        if ($RemovedCount -eq 0) {
            return 'Saved additional permissions already reconciled; no manifest-covered entries to remove.'
        }

        $Entity = @{
            'PartitionKey' = 'CIPP-SAM'
            'RowKey'       = 'CIPP-SAM'
            'Permissions'  = [string]([PSCustomObject]$Extras | ConvertTo-Json -Depth 10 -Compress)
            'UpdatedBy'    = $UpdatedBy
        }
        $null = Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force

        $Plural = if ($RemovedCount -eq 1) { 'entry' } else { 'entries' }
        return "Reconciled saved additional permissions: removed $RemovedCount $Plural now covered by the CIPP manifest."
    } catch {
        throw "Failed to reconcile permissions: $($_.Exception.Message)"
    }
}
