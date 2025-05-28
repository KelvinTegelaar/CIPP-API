function Add-CIPPDelegatedPermission {
    [CmdletBinding()]
    param(
        $RequiredResourceAccess,
        $TemplateId,
        $ApplicationId,
        $NoTranslateRequired,
        $Tenantfilter
    )
    Write-Host 'Adding Delegated Permissions'
    Set-Location (Get-Item $PSScriptRoot).FullName

    if ($ApplicationId -eq $env:ApplicationID -and $Tenantfilter -eq $env:TenantID) {
        #return @('Cannot modify delgated permissions for CIPP-SAM on partner tenant')
        $RequiredResourceAccess = 'CIPPDefaults'
    }

    if ($RequiredResourceAccess -eq 'CIPPDefaults') {
        $Permissions = Get-CippSamPermissions -NoDiff
        $NoTranslateRequired = $Permissions.Type -eq 'Table'
        $RequiredResourceAccess = [System.Collections.Generic.List[object]]::new()
        foreach ($AppId in $Permissions.Permissions.PSObject.Properties.Name) {
            $DelegatedPermissions = @($Permissions.Permissions.$AppId.delegatedPermissions)
            $ResourceAccess = [System.Collections.Generic.List[object]]::new()
            foreach ($Permission in $DelegatedPermissions) {
                $ResourceAccess.Add(@{
                        id   = $Permission.value
                        type = 'Scope'
                    })
            }
            $Resource = @{
                resourceAppId  = $AppId
                resourceAccess = @($ResourceAccess)
            }
            $RequiredResourceAccess.Add($Resource)
        }

        if ($Tenantfilter -eq $env:TenantID -or $Tenantfilter -eq 'PartnerTenant') {
            $RequiredResourceAccess = $RequiredResourceAccess + ($AdditionalPermissions | Where-Object { $RequiredResourceAccess.resourceAppId -notcontains $_.resourceAppId })
        } else {
            # remove the partner center permission if not pushing to partner tenant
            $RequiredResourceAccess = $RequiredResourceAccess | Where-Object { $_.resourceAppId -ne 'fa3d9a0c-3fb0-42cc-9193-47c7ecd2edbd' }
        }
    } else {
        if (!$RequiredResourceAccess -and $TemplateId) {
            Write-Information "Adding delegated permissions for template $TemplateId"
            $TemplateTable = Get-CIPPTable -TableName 'templates'
            $Filter = "RowKey eq '$TemplateId' and PartitionKey eq 'AppApprovalTemplate'"
            $Template = (Get-CIPPAzDataTableEntity @TemplateTable -Filter $Filter).JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
            $ApplicationId = $Template.AppId
            $Permissions = $Template.Permissions
            $NoTranslateRequired = $true
            $RequiredResourceAccess = [System.Collections.Generic.List[object]]::new()
            foreach ($AppId in $Permissions.PSObject.Properties.Name) {
                $DelegatedPermissions = @($Permissions.$AppId.delegatedPermissions)
                $ResourceAccess = [System.Collections.Generic.List[object]]::new()
                foreach ($Permission in $DelegatedPermissions) {
                    $ResourceAccess.Add(@{
                            id   = $Permission.value
                            type = 'Scope'
                        })
                }
                $Resource = @{
                    resourceAppId  = $AppId
                    resourceAccess = @($ResourceAccess)
                }
                $RequiredResourceAccess.Add($Resource)
            }
        }
    }

    $Translator = Get-Content '.\PermissionsTranslator.json' | ConvertFrom-Json
    $ServicePrincipalList = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=appId,id,displayName&`$top=999" -tenantid $Tenantfilter -skipTokenCache $true -NoAuthCheck $true
    $ourSVCPrincipal = $ServicePrincipalList | Where-Object -Property appId -EQ $ApplicationId
    $Results = [System.Collections.Generic.List[string]]::new()

    $CurrentDelegatedScopes = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals/$($ourSVCPrincipal.id)/oauth2PermissionGrants" -skipTokenCache $true -tenantid $Tenantfilter -NoAuthCheck $true

    foreach ($App in $RequiredResourceAccess) {
        if (!$App) {
            continue
        }
        $svcPrincipalId = $ServicePrincipalList | Where-Object -Property appId -EQ $App.resourceAppId
        if (!$svcPrincipalId) {
            try {
                $Body = @{
                    appId = $App.resourceAppId
                } | ConvertTo-Json -Compress
                $svcPrincipalId = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/servicePrincipals' -tenantid $Tenantfilter -body $Body -type POST -NoAuthCheck $true
            } catch {
                $Results.add("Failed to create service principal for $($App.resourceAppId): $(Get-NormalizedError -message $_.Exception.Message)")
                continue
            }
        }

        $DelegatedScopes = $App.resourceAccess | Where-Object -Property type -EQ 'Scope'

        if ($NoTranslateRequired) {
            $NewScope = @($DelegatedScopes | ForEach-Object { $_.id } | Sort-Object -Unique) -join ' '
        } else {
            $NewScope = foreach ($Scope in $DelegatedScopes.id) {
                if ($Scope -match '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$') {
                    $TranslatedScope = ($Translator | Where-Object -Property id -EQ $Scope).value
                    if ($TranslatedScope) {
                        $TranslatedScope
                    }
                } else {
                    $Scope
                }
            }
            $NewScope = (@($NewScope) | Sort-Object -Unique) -join ' '
        }

        $OldScope = ($CurrentDelegatedScopes | Where-Object -Property Resourceid -EQ $svcPrincipalId.id)

        if (!$OldScope) {
            try {
                $Createbody = @{
                    clientId    = $ourSVCPrincipal.id
                    consentType = 'AllPrincipals'
                    resourceId  = $svcPrincipalId.id
                    scope       = $NewScope
                } | ConvertTo-Json -Compress
                $CreateRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants' -tenantid $Tenantfilter -body $Createbody -type POST -NoAuthCheck $true
                $Results.add("Successfully added permissions for $($svcPrincipalId.displayName)")
            } catch {
                $Results.add("Failed to add permissions for $($svcPrincipalId.displayName): $(Get-NormalizedError -message $_.Exception.Message)")
                continue
            }
        } else {
            # Cleanup multiple scope entries and patch first id
            if (($OldScope.id | Measure-Object).Count -gt 1) {
                $OldScopeId = $OldScope.id[0]
                $OldScope.id | ForEach-Object {
                    if ($_ -ne $OldScopeId) {
                        try {
                            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$_" -tenantid $Tenantfilter -type DELETE -NoAuthCheck $true
                        } catch {
                        }
                    }
                }
            } else {
                $OldScopeId = $OldScope.id
            }
            $compare = Compare-Object -ReferenceObject $OldScope.scope.Split(' ') -DifferenceObject $NewScope.Split(' ')
            if (!$compare) {
                $Results.add("All delegated permissions exist for $($svcPrincipalId.displayName)")
                continue
            }
            $Patchbody = @{
                scope = "$NewScope"
            } | ConvertTo-Json -Compress
            try {
                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$($OldScopeId)" -tenantid $Tenantfilter -body $Patchbody -type PATCH -NoAuthCheck $true
            } catch {
                $Results.add("Failed to update permissions for $($svcPrincipalId.displayName): $(Get-NormalizedError -message $_.Exception.Message)")
                continue
            }
            # Added permissions
            $Added = ($Compare | Where-Object { $_.SideIndicator -eq '=>' }).InputObject -join ' '
            $Removed = ($Compare | Where-Object { $_.SideIndicator -eq '<=' }).InputObject -join ' '
            $Results.add("Successfully updated permissions for $($svcPrincipalId.displayName). $(if ($Added) { "Added: $Added"}) $(if ($Removed) { "Removed: $Removed"})")
        }
    }

    return $Results
}
