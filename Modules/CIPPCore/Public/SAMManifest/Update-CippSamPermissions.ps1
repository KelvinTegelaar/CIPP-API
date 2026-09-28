function Update-CippSamPermissions {
    <#
    .SYNOPSIS
        Reconciles the applied CIPP-SAM permission set in the AppPermissions table.
    .DESCRIPTION
        Writes the full applied permission set - the SAM manifest base PLUS any admin-configured extra
        permissions - into the AppPermissions table, so the table always reflects everything the
        CIPP-SAM app is expected to have. Get-CippSamPermissions diffs the manifest against this table
        to decide when a Permissions repair is needed, so persisting the manifest here is what lets that
        check clear after a repair.

        It deliberately does NOT write the partner CIPP-SAM app registration's requiredResourceAccess.
        Permissions reach the CIPP-SAM service principal(s) - partner and clients - through the grant
        flow (Add-CIPPApplicationPermission / Add-CIPPDelegatedPermission, which read this table), not
        through the app registration.
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
        # Manifest base - the always-required permissions.
        $ManifestPermissions = (Get-CippSamPermissions -ManifestOnly).Permissions

        $Table = Get-CIPPTable -TableName 'AppPermissions'
        $SavedRow = Get-CippAzDataTableEntity @Table -Filter "PartitionKey eq 'CIPP-SAM' and RowKey eq 'CIPP-SAM'"
        $Saved = $null
        if ($SavedRow.Permissions) {
            try {
                $Saved = $SavedRow.Permissions | ConvertFrom-Json -ErrorAction Stop
            } catch {
                $Saved = $null
            }
        }

        # Build the full applied set = manifest base ∪ admin extras, keyed by resource appId.
        $Applied = @{}
        $AppIds = @(@($ManifestPermissions.PSObject.Properties.Name) + @($Saved.PSObject.Properties.Name)) | Where-Object { $_ } | Sort-Object -Unique
        foreach ($AppId in $AppIds) {
            $ManifestApp = $ManifestPermissions.$AppId
            $SavedApp = $Saved.$AppId
            $ManifestAppIds = @($ManifestApp.applicationPermissions.id)
            $ManifestDelIds = @($ManifestApp.delegatedPermissions.id)

            $AppPerms = [System.Collections.Generic.List[object]]::new()
            $DelPerms = [System.Collections.Generic.List[object]]::new()

            # Manifest base (always applied).
            foreach ($Permission in $ManifestApp.applicationPermissions) {
                $AppPerms.Add([PSCustomObject]@{ id = $Permission.id; value = $Permission.value })
            }
            foreach ($Permission in $ManifestApp.delegatedPermissions) {
                $DelPerms.Add([PSCustomObject]@{ id = $Permission.id; value = $Permission.value })
            }
            # Admin extras (anything the manifest does not already cover).
            foreach ($Permission in $SavedApp.applicationPermissions) {
                if ($Permission.id -and $ManifestAppIds -notcontains $Permission.id) {
                    $AppPerms.Add([PSCustomObject]@{ id = $Permission.id; value = $Permission.value })
                }
            }
            foreach ($Permission in $SavedApp.delegatedPermissions) {
                if ($Permission.id -and $ManifestDelIds -notcontains $Permission.id) {
                    $DelPerms.Add([PSCustomObject]@{ id = $Permission.id; value = $Permission.value })
                }
            }

            if ($AppPerms.Count -gt 0 -or $DelPerms.Count -gt 0) {
                $Applied.$AppId = @{
                    applicationPermissions = @($AppPerms)
                    delegatedPermissions   = @($DelPerms)
                }
            }
        }

        $Entity = @{
            'PartitionKey' = 'CIPP-SAM'
            'RowKey'       = 'CIPP-SAM'
            'Permissions'  = [string]([PSCustomObject]$Applied | ConvertTo-Json -Depth 10 -Compress)
            'UpdatedBy'    = $UpdatedBy
        }
        $null = Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force

        return 'CIPP-SAM permissions reconciled: the applied permission table now contains the CIPP manifest permissions plus any additional permissions.'
    } catch {
        throw "Failed to reconcile permissions: $($_.Exception.Message)"
    }
}
