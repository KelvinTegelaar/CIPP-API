function Invoke-ExecSAMAppPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    switch ($Request.Query.Action) {
        'Update' {
            try {
                $Permissions = $Request.Body.Permissions
                $Entity = @{
                    'PartitionKey' = 'CIPP-SAM'
                    'RowKey'       = 'CIPP-SAM'
                    'Permissions'  = [string]($Permissions | ConvertTo-Json -Depth 10 -Compress)
                }
                $Table = Get-CIPPTable -TableName 'AppPermissions'
                $null = Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
                $Body = @{
                    'Results' = 'Permissions Updated'
                }
            } catch {
                $Body = @{
                    'Results' = $_.Exception.Message
                }
            }
        }
        default {
            $ModuleBase = Get-Module -Name CIPPCore | Select-Object -ExpandProperty ModuleBase
            $SamManifest = Get-Item "$ModuleBase\Public\SAMManifest.json"
            $AdditionalPermissions = Get-Item "$ModuleBase\Public\AdditionalPermissions.json"

            $LastWrite = @{
                'SAMManifest'           = $SamManifest.LastWriteTime
                'AdditionalPermissions' = $AdditionalPermissions.LastWriteTime
            }

            $ServicePrincipals = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/servicePrincipals?$top=999&$select=appId,displayName,appRoles,publishedPermissionScopes' -tenantid $env:TenantID -NoAuthCheck $true
            $SAMManifest = Get-Content -Path $SamManifest.FullName | ConvertFrom-Json
            $AdditionalPermissions = Get-Content -Path $AdditionalPermissions.FullName | ConvertFrom-Json

            $RequiredResources = $SamManifest.requiredResourceAccess

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

            $Body = @{
                'Permissions' = $Permissions
                'LastUpdate'  = $LastWrite
            }
        }
    }


    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ConvertTo-Json -Depth 10 -InputObject $Body
        })

}
