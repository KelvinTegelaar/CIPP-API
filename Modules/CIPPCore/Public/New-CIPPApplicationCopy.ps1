function New-CIPPApplicationCopy {
    [CmdletBinding()]
    param(
        $App,
        $Tenant
    )

    Write-Information "Copying application $($App) to tenant $Tenant"
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/v1.0/servicePrincipals?$top=999' -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true

    if ($CurrentInfo.appId -notcontains $App) {
        Write-Information "Application $($App) not found in partner tenant. Cannot copy permissions."
        throw 'We cannot copy permissions for this application because is not registered in the partner tenant.'
    }

    try {
        try {
            $ExistingApp = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/applications(appId='$($app)')" -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true
            $Type = 'Application'
        } catch {
            $ExistingApp = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals(appId='$($app)')/oauth2PermissionGrants" -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true
            $ExistingAppRoleAssignments = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals(appId='$($app)')/appRoleAssignments" -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true
            $Type = 'ServicePrincipal'
        }
        if (!$ExistingApp -and !$ExistingAppRoleAssignments) {
            Write-LogMessage -message "Failed to add $App to tenant. This app does not exist or does not have any consented permissions." -tenant $tenant -API 'Application Copy' -sev error
            continue
        }
        if ($Type -eq 'Application') {
            Write-Information 'App type: Application'
            $DelegateResourceAccess = $Existingapp.requiredResourceAccess
            $ApplicationResourceAccess = $Existingapp.requiredResourceAccess
            $NoTranslateRequired = $false
        } else {
            Write-Information 'App type: ServicePrincipal'
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
        $TenantInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/servicePrincipals?$top=999' -tenantid $Tenant -NoAuthCheck $true -AsApp $true

        if ($App -Notin $TenantInfo.appId) {
            Write-Information "Creating service principal with ID: $($App)"
            $Body = @{
                appId = $App
            }
            $Body = $Body | ConvertTo-Json -Compress
            Write-Information ($Body | ConvertTo-Json -Depth 10)
            $null = New-GraphPostRequest 'https://graph.microsoft.com/v1.0/servicePrincipals' -type POST -tenantid $Tenant -body $Body -AsApp $true
            Write-LogMessage -message "Added $App as a service principal" -tenant $tenant -API 'Application Copy' -sev Info

        } else {
            Write-Information "Service principal with ID: $($App) already exists in tenant $Tenant"
        }

        if ($DelegateResourceAccess) {
            Add-CIPPDelegatedPermission -RequiredResourceAccess $ApplicationResourceAccess -ApplicationId $App -Tenantfilter $Tenant
        }
        if ($ApplicationResourceAccess) {
            Add-CIPPApplicationPermission -RequiredResourceAccess $ApplicationResourceAccess -ApplicationId $App -Tenantfilter $Tenant
        }
        Write-LogMessage -message "Added permissions to $app" -tenant $tenant -API 'Application Copy' -sev Info

        return $Results
    } catch {
        Write-Warning "Failed to copy application $($App) to tenant $Tenant. Error: $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
        Write-Information ($_.ScriptStackTrace | Out-String)
        throw $_.Exception.Message
    }
}
