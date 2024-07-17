function New-CIPPApplicationCopy {
    [CmdletBinding()]
    param(
        $App,
        $Tenant
    )
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/servicePrincipals?$top=999' -tenantid $env:TenantID -NoAuthCheck $true
    try {
        $ExistingApp = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/Applications(appId='$($app)')" -tenantid $ENV:tenantid -NoAuthCheck $true
        $Type = 'Application'
    } catch {
        $ExistingApp = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals(appId='$($app)')/oauth2PermissionGrants" -tenantid $ENV:tenantid -NoAuthCheck $true
        $ExistingAppRoleAssignments = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals(appId='$($app)')/appRoleAssignments" -tenantid $ENV:tenantid -NoAuthCheck $true
        $Type = 'ServicePrincipal'
    }
    if (!$ExistingApp) {
        Write-LogMessage -message "Failed to add $App to tenant. This app does not exist." -tenant $tenant -API 'Application Copy' -sev error
        continue
    }
    if ($Type -eq 'Application') {
        $DelegateResourceAccess = $Existingapp.requiredResourceAccess
        $ApplicationResourceAccess = $Existingapp.requiredResourceAccess
        $NoTranslateRequired = $false
    } else {
        $DelegateResourceAccess = $ExistingApp | Group-Object -Property resourceId | ForEach-Object {
            [pscustomobject]@{ resourceAppId = ($CurrentInfo | Where-Object -Property id -EQ $_.Name).appId; resourceAccess = @($_.Group | ForEach-Object { [pscustomobject]@{ id = $_.scope; type = 'Scope' } } )
            }
        }
        $ApplicationResourceAccess = $ExistingappRoleAssignments | Group-Object -Property ResourceId | ForEach-Object {
            [pscustomobject]@{ resourceAppId = ($CurrentInfo | Where-Object -Property id -EQ $_.Name).appId; resourceAccess = @($_.Group | ForEach-Object { [pscustomobject]@{ id = $_.appRoleId; type = 'Role' } } )
            }
        }
        $NoTranslateRequired = $true
    }
    $TenantInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/servicePrincipals?$top=999' -tenantid $Tenant -NoAuthCheck $true

    if ($App -Notin $TenantInfo.appId) {
        $null = New-GraphPostRequest 'https://graph.microsoft.com/beta/servicePrincipals' -type POST -tenantid $Tenant -body "{ `"appId`": `"$($App)`" }"
        Write-LogMessage -message "Added $App as a service principal" -tenant $tenant -API 'Application Copy' -sev Info
    }
    Add-CIPPApplicationPermission -RequiredResourceAccess $ApplicationResourceAccess -ApplicationId $App -Tenantfilter $Tenant
    Add-CIPPDelegatedPermission -RequiredResourceAccess $DelegateResourceAccess -ApplicationId $App -Tenantfilter $Tenant -NoTranslateRequired $NoTranslateRequired
    Write-LogMessage -message "Added permissions to $app" -tenant $tenant -API 'Application Copy' -sev Info

    return $Results
}
