function Push-ExecAppApprovalTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    try {
        $Item = $Item | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $TemplateId = $Item.templateId
        if (!$TemplateId) {
            Write-LogMessage -message 'No template specified' -tenant $Item.Tenant -API 'Add Multitenant App' -sev Error
            return $false
        }

        # Get the template data to determine if it's a Gallery Template or Enterprise App
        $Table = Get-CIPPTable -TableName 'templates'
        $Template = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'AppApprovalTemplate' and RowKey eq '$TemplateId'"

        if (!$Template) {
            Write-LogMessage -message "Template $TemplateId not found" -tenant $Item.Tenant -API 'Add Multitenant App' -sev Error
            return $false
        }

        $TemplateData = $Template.JSON | ConvertFrom-Json
        # Default to EnterpriseApp for backward compatibility with older templates
        $AppType = $TemplateData.AppType
        if (-not $AppType) {
            $AppType = 'EnterpriseApp'
        }

        # Handle Gallery Templates
        if ($AppType -eq 'GalleryTemplate') {
            Write-Information "Deploying Gallery Template $($TemplateData.AppName) to tenant $($Item.Tenant)."

            # Use the Gallery Template instantiation API
            $GalleryTemplateId = $TemplateData.GalleryTemplateId
            if (!$GalleryTemplateId) {
                Write-LogMessage -message 'Gallery Template ID not found in template data' -tenant $Item.Tenant -API 'Add Multitenant App' -sev Error
                return $false
            }

            # Check if the app already exists in the tenant
            $ServicePrincipalList = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=AppId,id,displayName&`$top=999" -tenantid $Item.Tenant
            if ($TemplateData.GalleryTemplateId -in $ServicePrincipalList.applicationTemplateId) {
                Write-LogMessage -message "Gallery Template app $($TemplateData.AppName) already exists in tenant $($Item.Tenant)" -tenant $Item.Tenant -API 'Add Gallery App' -sev Info
                return $true
            }

            # Instantiate the gallery template
            $InstantiateBody = @{
                displayName = $TemplateData.AppName
            } | ConvertTo-Json -Depth 10

            $InstantiateResult = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/applicationTemplates/$GalleryTemplateId/instantiate" -type POST -tenantid $Item.tenant -body $InstantiateBody

            if ($InstantiateResult.application.appId) {
                Write-LogMessage -message "Successfully deployed Gallery Template $($TemplateData.AppName) to tenant $($Item.Tenant). Application ID: $($InstantiateResult.application.appId)" -tenant $Item.Tenant -API 'Add Gallery App' -sev Info
                # Get application registration
                $App = $InstantiateResult.application.appId
                $Application = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/applications(appId='$App')" -tenantid $Item.tenant -AsApp $true
                if ($Application.requiredResourceAccess) {
                    Add-CIPPDelegatedPermission -RequiredResourceAccess $Application.requiredResourceAccess -ApplicationId $App -Tenantfilter $Item.Tenant
                    Add-CIPPApplicationPermission -RequiredResourceAccess $Application.requiredResourceAccess -ApplicationId $App -Tenantfilter $Item.Tenant
                }
            } else {
                Write-LogMessage -message "Gallery Template deployment completed but application ID not returned for $($TemplateData.AppName) in tenant $($Item.Tenant)" -tenant $Item.Tenant -API 'Add Gallery App' -sev Warning
            }

        } elseif ($AppType -eq 'ApplicationManifest') {
            Write-Information "Deploying Application Manifest $($TemplateData.AppName) to tenant $($Item.Tenant)."

            # Get the application manifest from template data
            $ApplicationManifest = $TemplateData.ApplicationManifest
            if (!$ApplicationManifest) {
                Write-LogMessage -message 'Application Manifest not found in template data' -tenant $Item.Tenant -API 'Add Multitenant App' -sev Error
                return $false
            }

            # Check for existing application by display name
            $ServicePrincipalList = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=AppId,id,displayName&`$top=999" -tenantid $Item.Tenant
            $ExistingApp = $ServicePrincipalList | Where-Object { $_.displayName -eq $TemplateData.AppName }
            if ($ExistingApp) {
                Write-LogMessage -message "Application with name '$($TemplateData.AppName)' already exists in tenant $($Item.Tenant)" -tenant $Item.Tenant -API 'Add App Manifest' -sev Info

                # get existing application
                $App = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/applications(appId='$($ExistingApp.appId)')" -tenantid $Item.Tenant

                # compare permissions
                $ExistingPermissions = $App.requiredResourceAccess | ConvertTo-Json -Depth 10
                $NewPermissions = $ApplicationManifest.requiredResourceAccess | ConvertTo-Json -Depth 10
                if ($ExistingPermissions -ne $NewPermissions) {
                    Write-LogMessage -message "Updating permissions for existing application '$($TemplateData.AppName)' in tenant $($Item.Tenant)" -tenant $Item.Tenant -API 'Add App Manifest' -sev Info

                    # Update permissions for existing application
                    $UpdateBody = @{
                        requiredResourceAccess = $ApplicationManifest.requiredResourceAccess
                    } | ConvertTo-Json -Depth 10
                    $null = New-GraphPostRequest -type PATCH -uri "https://graph.microsoft.com/beta/applications(appId='$($ExistingApp.appId)')" -tenantid $Item.Tenant -body $UpdateBody

                    # consent new permissions
                    Add-CIPPDelegatedPermission -RequiredResourceAccess $ApplicationManifest.requiredResourceAccess -ApplicationId $ExistingApp.appId -Tenantfilter $Item.Tenant
                    Add-CIPPApplicationPermission -RequiredResourceAccess $ApplicationManifest.requiredResourceAccess -ApplicationId $ExistingApp.appId -Tenantfilter $Item.Tenant
                }

                return $true
            }

            $PropertiesToRemove = @('appId', 'id', 'createdDateTime', 'publisherDomain', 'servicePrincipalLockConfiguration', 'identifierUris', 'applicationIdUris')

            # Strip tenant-specific data that might cause conflicts
            $CleanManifest = $ApplicationManifest | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            foreach ($Property in $PropertiesToRemove) {
                $CleanManifest.PSObject.Properties.Remove($Property)
            }

            # Create the application from manifest
            try {
                $CreateBody = $CleanManifest | ConvertTo-Json -Depth 10
                $CreatedApp = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/applications' -type POST -tenantid $Item.tenant -body $CreateBody

                if ($CreatedApp.appId) {
                    # Create service principal for the application
                    $ServicePrincipalBody = @{
                        appId = $CreatedApp.appId
                    } | ConvertTo-Json

                    $null = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/servicePrincipals' -type POST -tenantid $Item.tenant -body $ServicePrincipalBody

                    Write-LogMessage -message "Successfully deployed Application Manifest $($TemplateData.AppName) to tenant $($Item.Tenant). Application ID: $($CreatedApp.appId)" -tenant $Item.Tenant -API 'Add App Manifest' -sev Info

                    if ($CreatedApp.requiredResourceAccess) {
                        Add-CIPPDelegatedPermission -RequiredResourceAccess $CreatedApp.requiredResourceAccess -ApplicationId $CreatedApp.appId -Tenantfilter $Item.Tenant
                        Add-CIPPApplicationPermission -RequiredResourceAccess $CreatedApp.requiredResourceAccess -ApplicationId $CreatedApp.appId -Tenantfilter $Item.Tenant
                    }
                } else {
                    Write-LogMessage -message "Application Manifest deployment failed - no application ID returned for $($TemplateData.AppName) in tenant $($Item.Tenant)" -tenant $Item.Tenant -API 'Add App Manifest' -sev Error
                }
            } catch {
                Write-LogMessage -message "Error creating application from manifest in tenant $($Item.Tenant) - $($_.Exception.Message)" -tenant $Item.Tenant -API 'Add App Manifest' -sev Error
                throw $_.Exception.Message
            }

        } else {
            # Handle Enterprise Apps (existing logic)
            $ServicePrincipalList = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=AppId,id,displayName&`$top=999" -tenantid $Item.Tenant
            if ($Item.AppId -notin $ServicePrincipalList.appId) {
                Write-Information "Adding $($Item.AppId) to tenant $($Item.Tenant)."
                $PostResults = New-GraphPostRequest 'https://graph.microsoft.com/beta/servicePrincipals' -type POST -tenantid $Item.tenant -body "{ `"appId`": `"$($Item.appId)`" }"
                Write-LogMessage -message "Added $($Item.AppId) to tenant $($Item.Tenant)" -tenant $Item.Tenant -API 'Add Multitenant App' -sev Info
            } else {
                Write-LogMessage -message "This app already exists in tenant $($Item.Tenant). We're adding the required permissions." -tenant $Item.Tenant -API 'Add Multitenant App' -sev Info
            }
            Add-CIPPApplicationPermission -TemplateId $TemplateId -Tenantfilter $Item.Tenant
            Add-CIPPDelegatedPermission -TemplateId $TemplateId -Tenantfilter $Item.Tenant
        }
    } catch {
        Write-LogMessage -message "Error adding application to tenant $($Item.Tenant) - $($_.Exception.Message)" -tenant $Item.Tenant -API 'Add Multitenant App' -sev Error
        Write-Error $_.Exception.Message
    }
}
