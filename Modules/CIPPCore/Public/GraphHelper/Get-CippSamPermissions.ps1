function Get-CippSamPermissions {
    <#
    .SYNOPSIS
    This script retrieves the CIPP-SAM permissions.

    .DESCRIPTION
    Retrieves the CIPP-SAM permissions as a layered set: the permissions defined in the SAM manifest
    files (SAMManifest.json + AdditionalPermissions.json) are ALWAYS treated as the required base and
    can never be removed. Any permissions saved in the AppPermissions table are treated as EXTRAS that
    are layered on top of (not instead of) the manifest base.

    The effective set returned in .Permissions is therefore always manifest ∪ extras. Each permission
    is annotated with a 'required' boolean so the UI can lock the manifest-defined defaults.

    Unless -NoDiff is used, the function also pulls the live CIPP-SAM application registration from the
    partner tenant and diffs its requiredResourceAccess against the effective set, surfacing
    permissions that need to be added to (MissingPermissions) and removed from (PartnerAppDiff) the app.

    .EXAMPLE
    Get-CippSamPermissions
    Returns the effective permission set plus the partner app drift diff.

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param(
        [Parameter(ParameterSetName = 'ManifestOnly')]
        [switch]$ManifestOnly,
        [Parameter(ParameterSetName = 'Default')]
        [switch]$SavedOnly,
        [Parameter(ParameterSetName = 'Diff')]
        [switch]$NoDiff
    )

    $GuidRegex = '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$'

    if (!$SavedOnly.IsPresent) {
        # Return cached result if available and less than 5 minutes old (avoids duplicate partner-tenant Graph calls within same invocation)
        if ($NoDiff.IsPresent -and $script:CippSamPermissionsCache -and
            $script:CippSamPermissionsCacheTime -and
            ((Get-Date) - $script:CippSamPermissionsCacheTime).TotalMinutes -lt 5) {
            return $script:CippSamPermissionsCache
        }

        $SamManifestFile = Get-Item (Join-Path $env:CIPPRootPath 'Config\SAMManifest.json')
        $AdditionalPermissionsFile = Get-Item (Join-Path $env:CIPPRootPath 'Config\AdditionalPermissions.json')

        $ServicePrincipalList = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/servicePrincipals?$top=999&$select=id,appId,displayName' -tenantid $env:TenantID -NoAuthCheck $true

        $SAMManifest = Get-Content -Path $SamManifestFile.FullName | ConvertFrom-Json
        $AdditionalPermissions = Get-Content -Path $AdditionalPermissionsFile.FullName | ConvertFrom-Json

        $RequiredResources = $SAMManifest.requiredResourceAccess

        $AppIds = ($RequiredResources.resourceAppId + $AdditionalPermissions.resourceAppId) | Sort-Object -Unique

        Write-Information "Retrieving service principals for $($AppIds.Count) applications"
        $UsedServicePrincipals = $ServicePrincipalList | Where-Object -Property appId -In $AppIds
        $Requests = $UsedServicePrincipals | ForEach-Object {
            @(
                @{
                    id     = $_.id
                    url    = 'servicePrincipals/{0}?$select=appId,displayName,appRoles,publishedPermissionScopes' -f $_.id
                    method = 'GET'
                }
            )
        }
        $BulkRequests = New-GraphBulkRequest -Requests $Requests -NoAuthCheck $true -tenantid $env:TenantID
        $ServicePrincipals = $BulkRequests | ForEach-Object {
            $_.body
        }

        # Build the manifest (required / default) permission set. These are immutable and always required.
        $ManifestPermissions = @{}
        foreach ($AppId in $AppIds) {
            $ServicePrincipal = $ServicePrincipals | Where-Object -Property appId -EQ $AppId
            $AppPermissions = [System.Collections.Generic.List[object]]@()
            $ManifestResourceAccess = ($RequiredResources | Where-Object -Property resourceAppId -EQ $AppId).resourceAccess
            $UnpublishedPermissions = ($AdditionalPermissions | Where-Object -Property resourceAppId -EQ $AppId).resourceAccess

            foreach ($Permission in $ManifestResourceAccess) {
                $AppPermissions.Add($Permission)
            }
            if ($UnpublishedPermissions) {
                foreach ($Permission in $UnpublishedPermissions) {
                    $AppPermissions.Add($Permission)
                }
            }

            $ApplicationPermissions = [System.Collections.Generic.List[object]]@()
            $DelegatedPermissions = [System.Collections.Generic.List[object]]@()
            foreach ($Permission in $AppPermissions) {
                if ($Permission.id -match $GuidRegex) {
                    if ($Permission.type -eq 'Role') {
                        $PermissionName = ($ServicePrincipal.appRoles | Where-Object -Property id -EQ $Permission.id).value
                    } else {
                        $PermissionName = ($ServicePrincipal.publishedPermissionScopes | Where-Object -Property id -EQ $Permission.id).value
                    }
                } else {
                    $PermissionName = $Permission.id
                }

                $Entry = [PSCustomObject]@{
                    id       = $Permission.id
                    value    = $PermissionName
                    required = $true
                }
                if ($Permission.type -eq 'Role') {
                    $ApplicationPermissions.Add($Entry)
                } else {
                    $DelegatedPermissions.Add($Entry)
                }
            }

            $ManifestPermissions.$AppId = @{
                applicationPermissions = @($ApplicationPermissions | Sort-Object -Property value)
                delegatedPermissions   = @($DelegatedPermissions | Sort-Object -Property value)
            }
        }
    }

    if ($ManifestOnly) {
        return [PSCustomObject]@{
            Permissions = [PSCustomObject]$ManifestPermissions
            Type        = 'Manifest'
        }
    }

    # Load the saved EXTRA permissions (layered on top of the manifest base)
    $Table = Get-CippTable -tablename 'AppPermissions'
    $SavedRow = Get-CippAzDataTableEntity @Table -Filter "PartitionKey eq 'CIPP-SAM' and RowKey eq 'CIPP-SAM'"
    if ($SavedRow.Permissions) {
        try {
            $SavedPermissions = $SavedRow.Permissions | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $SavedPermissions = [PSCustomObject]@{}
        }
    } else {
        $SavedPermissions = [PSCustomObject]@{}
    }

    if ($SavedOnly.IsPresent) {
        return [PSCustomObject]@{
            Permissions = $SavedPermissions
            Type        = 'Table'
        }
    }

    # Build the effective set = manifest (required) ∪ saved extras (required = false).
    # Manifest permissions are always present, so a stale/edited saved set can never drop a required scope.
    $EffectivePermissions = @{}
    $AdditionalOnly = @{}
    $AllAppIds = @(@($ManifestPermissions.Keys) + @($SavedPermissions.PSObject.Properties.Name)) | Where-Object { $_ } | Sort-Object -Unique

    foreach ($AppId in $AllAppIds) {
        $ManifestApp = $ManifestPermissions.$AppId
        $SavedApp = $SavedPermissions.$AppId

        $ManifestAppIds = @($ManifestApp.applicationPermissions.id)
        $ManifestDelIds = @($ManifestApp.delegatedPermissions.id)

        $EffApp = [System.Collections.Generic.List[object]]::new()
        $EffDel = [System.Collections.Generic.List[object]]::new()
        $ExtraApp = [System.Collections.Generic.List[object]]::new()
        $ExtraDel = [System.Collections.Generic.List[object]]::new()

        foreach ($Permission in $ManifestApp.applicationPermissions) { $EffApp.Add($Permission) }
        foreach ($Permission in $ManifestApp.delegatedPermissions) { $EffDel.Add($Permission) }

        foreach ($Permission in $SavedApp.applicationPermissions) {
            if ($Permission.id -and $ManifestAppIds -notcontains $Permission.id) {
                $Extra = [PSCustomObject]@{ id = $Permission.id; value = $Permission.value; required = $false }
                $EffApp.Add($Extra)
                $ExtraApp.Add($Extra)
            }
        }
        foreach ($Permission in $SavedApp.delegatedPermissions) {
            if ($Permission.id -and $ManifestDelIds -notcontains $Permission.id) {
                $Extra = [PSCustomObject]@{ id = $Permission.id; value = $Permission.value; required = $false }
                $EffDel.Add($Extra)
                $ExtraDel.Add($Extra)
            }
        }

        $EffectivePermissions.$AppId = @{
            applicationPermissions = @($EffApp | Sort-Object -Property value)
            delegatedPermissions   = @($EffDel | Sort-Object -Property value)
        }
        if ($ExtraApp.Count -gt 0 -or $ExtraDel.Count -gt 0) {
            $AdditionalOnly.$AppId = @{
                applicationPermissions = @($ExtraApp)
                delegatedPermissions   = @($ExtraDel)
            }
        }
    }

    # Diff the effective set against the live CIPP-SAM application registration in the partner tenant.
    # MissingPermissions = effective perms not yet on the app (need to be added).
    # PartnerAppDiff also surfaces extra perms on the app that are not in the effective set (need to be removed).
    $MissingPermissions = @{}
    $PartnerAppDiff = @{}
    if (!$NoDiff.IsPresent) {
        try {
            $PartnerApp = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/applications(appId='$($env:ApplicationID)')?`$select=requiredResourceAccess" -tenantid $env:TenantID -NoAuthCheck $true
            foreach ($AppId in $AllAppIds) {
                $ServicePrincipal = $ServicePrincipals | Where-Object -Property appId -EQ $AppId
                $AppRegResource = $PartnerApp.requiredResourceAccess | Where-Object -Property resourceAppId -EQ $AppId
                $AppRegRoleIds = @(($AppRegResource.resourceAccess | Where-Object { $_.type -eq 'Role' }).id)
                $AppRegScopeIds = @(($AppRegResource.resourceAccess | Where-Object { $_.type -eq 'Scope' }).id)

                # Only GUID-based permissions live in the app registration's requiredResourceAccess.
                # String-named scopes (e.g. the .Sdp AdditionalPermissions) are applied as direct grants,
                # so excluding them here avoids permanent false-positive "missing" entries.
                $EffApp = @($EffectivePermissions.$AppId.applicationPermissions | Where-Object { $_.id -match $GuidRegex })
                $EffDel = @($EffectivePermissions.$AppId.delegatedPermissions | Where-Object { $_.id -match $GuidRegex })
                $EffAppIds = @($EffApp.id)
                $EffDelIds = @($EffDel.id)

                $MissingApp = @(foreach ($Permission in $EffApp) { if ($AppRegRoleIds -notcontains $Permission.id) { $Permission } })
                $MissingDel = @(foreach ($Permission in $EffDel) { if ($AppRegScopeIds -notcontains $Permission.id) { $Permission } })
                $ExtraApp = @(foreach ($Id in $AppRegRoleIds) {
                        if ($EffAppIds -notcontains $Id) {
                            [PSCustomObject]@{ id = $Id; value = (($ServicePrincipal.appRoles | Where-Object -Property id -EQ $Id).value) ?? $Id }
                        }
                    })
                $ExtraDel = @(foreach ($Id in $AppRegScopeIds) {
                        if ($EffDelIds -notcontains $Id) {
                            [PSCustomObject]@{ id = $Id; value = (($ServicePrincipal.publishedPermissionScopes | Where-Object -Property id -EQ $Id).value) ?? $Id }
                        }
                    })

                if ($MissingApp.Count -gt 0 -or $MissingDel.Count -gt 0) {
                    $MissingPermissions.$AppId = @{
                        applicationPermissions = $MissingApp
                        delegatedPermissions   = $MissingDel
                    }
                }
                if ($MissingApp.Count -gt 0 -or $MissingDel.Count -gt 0 -or $ExtraApp.Count -gt 0 -or $ExtraDel.Count -gt 0) {
                    $PartnerAppDiff.$AppId = @{
                        missingApplicationPermissions = $MissingApp
                        missingDelegatedPermissions   = $MissingDel
                        extraApplicationPermissions   = $ExtraApp
                        extraDelegatedPermissions     = $ExtraDel
                    }
                }
            }
        } catch {
            Write-Information "Failed to retrieve partner app registration for permission diff: $($_.Exception.Message)"
        }
    }

    $Timestamp = $SamManifestFile.LastWriteTime.ToUniversalTime()
    if ($SavedRow.Timestamp) {
        $SavedTimestamp = $SavedRow.Timestamp.DateTime.ToUniversalTime()
        if ($SavedTimestamp -gt $Timestamp) {
            $Timestamp = $SavedTimestamp
        }
    }

    $HasSaved = ($SavedPermissions.PSObject.Properties.Name | Measure-Object).Count -gt 0

    $SamAppPermissions = [PSCustomObject]@{
        Permissions           = [PSCustomObject]$EffectivePermissions
        DefaultPermissions    = [PSCustomObject]$ManifestPermissions
        AdditionalPermissions = [PSCustomObject]$AdditionalOnly
        MissingPermissions    = [PSCustomObject]$MissingPermissions
        PartnerAppDiff        = [PSCustomObject]$PartnerAppDiff
        UsedServicePrincipals = $UsedServicePrincipals
        Type                  = if ($HasSaved) { 'Table' } else { 'Manifest' }
        UpdatedBy             = $SavedRow.UpdatedBy ?? 'CIPP'
        Timestamp             = $Timestamp.ToString('yyyy-MM-ddTHH:mm:ssZ')
    }

    $SamAppPermissions = $SamAppPermissions | ConvertTo-Json -Depth 10 -Compress | ConvertFrom-Json

    if ($NoDiff.IsPresent) {
        $script:CippSamPermissionsCache = $SamAppPermissions
        $script:CippSamPermissionsCacheTime = Get-Date
    }

    return $SamAppPermissions
}
