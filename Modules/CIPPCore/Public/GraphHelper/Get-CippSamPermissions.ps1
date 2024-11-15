function Get-CippSamPermissions {
    <#
    .SYNOPSIS
    This script retrieves the CIPP-SAM permissions.

    .DESCRIPTION
    The Get-CippSamManifest function is used to retrieve the CIPP-SAM permissions either from the manifest files or table.

    .EXAMPLE
    Get-CippSamManifest
    Retrieves the CIPP SAM manifest located in the module root

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    Param(
        [Parameter(ParameterSetName = 'ManifestOnly')]
        [switch]$ManifestOnly,
        [Parameter(ParameterSetName = 'Default')]
        [switch]$SavedOnly,
        [Parameter(ParameterSetName = 'Diff')]
        [switch]$NoDiff
    )

    if (!$SavedOnly.IsPresent) {
        $ModuleBase = Get-Module -Name CIPPCore | Select-Object -ExpandProperty ModuleBase
        $SamManifestFile = Get-Item (Join-Path $ModuleBase "Public\SAMManifest.json")
        $AdditionalPermissions = Get-Item (Join-Path $ModuleBase "Public\AdditionalPermissions.json")

        $ServicePrincipals = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/servicePrincipals?$top=999&$select=appId,displayName,appRoles,publishedPermissionScopes' -tenantid $env:TenantID -NoAuthCheck $true
        $SAMManifest = Get-Content -Path $SamManifestFile.FullName | ConvertFrom-Json
        $AdditionalPermissions = Get-Content -Path $AdditionalPermissions.FullName | ConvertFrom-Json

        $RequiredResources = $SAMManifest.requiredResourceAccess

        $AppIds = ($RequiredResources.resourceAppId + $AdditionalPermissions.resourceAppId) | Sort-Object -Unique

        $Permissions = @{}
        foreach ($AppId in $AppIds) {
            $ServicePrincipal = $ServicePrincipals | Where-Object -Property appId -EQ $AppId
            $AppPermissions = [System.Collections.Generic.List[object]]@()
            $ManifestPermissions = ($RequiredResources | Where-Object -Property resourceAppId -EQ $AppId).resourceAccess
            $UnpublishedPermissions = ($AdditionalPermissions | Where-Object -Property resourceAppId -EQ $AppId).resourceAccess

            foreach ($Permission in $ManifestPermissions) {
                $AppPermissions.Add($Permission)
            }
            if ($UnpublishedPermissions) {
                foreach ($Permission in $UnpublishedPermissions) {
                    $AppPermissions.Add($Permission)
                }
            }

            $ApplicationPermissions = [system.collections.generic.list[object]]@()
            $DelegatedPermissions = [system.collections.generic.list[object]]@()
            foreach ($Permission in $AppPermissions) {
                if ($Permission.id -match '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$') {
                    if ($Permission.type -eq 'Role') {
                        $PermissionName = ($ServicePrincipal.appRoles | Where-Object -Property id -EQ $Permission.id).value
                    } else {
                        $PermissionName = ($ServicePrincipal.publishedPermissionScopes | Where-Object -Property id -EQ $Permission.id).value
                    }
                } else {
                    $PermissionName = $Permission.id
                }

                if ($Permission.type -eq 'Role') {
                    $ApplicationPermissions.Add([PSCustomObject]@{
                            id    = $Permission.id
                            value = $PermissionName

                        })
                } else {
                    $DelegatedPermissions.Add([PSCustomObject]@{
                            id    = $Permission.id
                            value = $PermissionName
                        })
                }
            }

            $ServicePrincipal = $ServicePrincipals | Where-Object -Property appId -EQ $AppId
            $Permissions.$AppId = @{
                applicationPermissions = @($ApplicationPermissions | Sort-Object -Property label)
                delegatedPermissions   = @($DelegatedPermissions | Sort-Object -Property label)
            }
        }
    }
    if ($ManifestOnly) {
        return [PSCustomObject]@{
            Permissions = $Permissions
            Type        = 'Manifest'
        }
    }

    $Table = Get-CippTable -tablename 'AppPermissions'
    $SavedPermissions = Get-CippAzDataTableEntity @Table -Filter "PartitionKey eq 'CIPP-SAM' and RowKey eq 'CIPP-SAM'"
    if ($SavedPermissions.Permissions) {
        $SavedPermissions.Permissions = $SavedPermissions.Permissions | ConvertFrom-Json
    } else {
        $SavedPermissions = @{
            Permissions = [PSCustomObject]@{}
        }
    }

    if ($SavedOnly.IsPresent) {
        $SavedPermissions | Add-Member -MemberType NoteProperty -Name Type -Value 'Table'
        return $SavedPermissions
    }

    if (!$NoDiff -and $SavedPermissions.Permissions) {
        $DiffPermissions = @{}
        foreach ($AppId in $AppIds) {
            $ManifestSpPermissions = $Permissions.$AppId
            $SavedSpPermission = $SavedPermissions.Permissions.$AppId
            $MissingApp = [System.Collections.Generic.List[object]]::new()
            $MissingDelegated = [System.Collections.Generic.List[object]]::new()
            foreach ($Permission in $ManifestSpPermissions.applicationPermissions) {
                if ($SavedSpPermission.applicationPermissions.id -notcontains $Permission.id) {
                    $MissingApp.Add($Permission)
                }
            }
            foreach ($Permission in $ManifestSpPermissions.delegatedPermissions) {
                if ($SavedSpPermission.delegatedPermissions.id -notcontains $Permission.id) {
                    $MissingDelegated.Add($Permission)
                }
            }
            if ($MissingApp -or $MissingDelegated) {
                $DiffPermissions.$AppId = @{
                    applicationPermissions = $MissingApp
                    delegatedPermissions   = $MissingDelegated
                }
            }
        }
    }

    $SamAppPermissions = @{}
    if (($SavedPermissions.Permissions.PSObject.Properties.Name | Measure-Object).Count -gt 0) {
        $SamAppPermissions.Permissions = $SavedPermissions.Permissions
        $SamAppPermissions.UpdatedBy = $SavedPermissions.UpdatedBy
        $SamAppPermissions.Timestamp = $SavedPermissions.Timestamp.DateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $SamAppPermissions.Type = 'Table'
    } else {
        $SamAppPermissions.Permissions = $Permissions
        $SamAppPermissions.Type = 'Manifest'
        $SamAppPermissions.UpdatedBy = 'CIPP'
        $SamAppPermissions.Timestamp = $SamManifestFile.LastWriteTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }

    if (!$NoDiff.IsPresent -and $SamAppPermissions.Type -eq 'Table') {
        $SamAppPermissions.MissingPermissions = $DiffPermissions
    }

    $SamAppPermissions = $SamAppPermissions | ConvertTo-Json -Depth 10 -Compress | ConvertFrom-Json

    return $SamAppPermissions
}

