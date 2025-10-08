function Invoke-CIPPStandardAppDeploy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AppDeploy
    .SYNOPSIS
        (Label) Deploy Application
    .DESCRIPTION
        (Helptext) Deploys selected applications to the tenant. Use a comma separated list of application IDs to deploy multiple applications. Permissions will be copied from the source application.
        (DocsDescription) Uses the CIPP functionality that deploys applications across an entire tenant base as a standard.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        EXECUTIVETEXT
            Automatically deploys approved business applications across all company locations and users, ensuring consistent access to essential tools and maintaining standardized software configurations. This streamlines application management and reduces IT deployment overhead.
        ADDEDCOMPONENT
            {"type":"select","multiple":false,"creatable":false,"label":"App Approval Mode","name":"standards.AppDeploy.mode","options":[{"label":"Template","value":"template"},{"label":"Copy Permissions","value":"copy"}]}
            {"type":"autoComplete","multiple":true,"creatable":false,"label":"Select Applications","name":"standards.AppDeploy.templateIds","api":{"url":"/api/ListAppApprovalTemplates","labelField":"TemplateName","valueField":"TemplateId","queryKey":"StdAppApprovalTemplateList","addedField":{"AppId":"AppId"}},"condition":{"field":"standards.AppDeploy.mode","compareType":"is","compareValue":"template"}}
            {"type":"textField","name":"standards.AppDeploy.appids","label":"Application IDs, comma separated","condition":{"field":"standards.AppDeploy.mode","compareType":"isNot","compareValue":"template"}}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-07-07
        POWERSHELLEQUIVALENT
            Portal or Graph API
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    Write-Information "Running AppDeploy standard for tenant $($Tenant)."

    $AppsToAdd = $Settings.appids -split ','
    $AppExists = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/servicePrincipals?$top=999' -tenantid $Tenant
    $Mode = $Settings.mode ?? 'copy'

    if ($Mode -eq 'template') {
        # For template mode, we need to check each template individually
        # since Gallery Templates and Enterprise Apps have different deployment methods
        $AppsToAdd = @()
        $Table = Get-CIPPTable -TableName 'templates'

        $AppsToAdd = foreach ($TemplateId in $Settings.templateIds.value) {
            $Template = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'AppApprovalTemplate' and RowKey eq '$TemplateId'"
            if ($Template) {
                $TemplateData = $Template.JSON | ConvertFrom-Json
                # Default to EnterpriseApp for backward compatibility with older templates
                $AppType = $TemplateData.AppType
                if (-not $AppType) {
                    $AppType = 'EnterpriseApp'
                }

                # Return different identifiers based on app type for checking
                if ($AppType -eq 'ApplicationManifest') {
                    # For Application Manifests, use display name for checking
                    $TemplateData.AppName
                } elseif ($AppType -eq 'GalleryTemplate') {
                    # For Gallery Templates, use gallery template ID
                    $TemplateData.GalleryTemplateId
                } else {
                    # For Enterprise Apps, use app ID
                    $TemplateData.AppId
                }
            }
        }
    }

    # Check for missing apps based on template type
    $MissingApps = [System.Collections.Generic.List[string]]::new()
    if ($Mode -eq 'template') {
        $Table = Get-CIPPTable -TableName 'templates'
        foreach ($TemplateId in $Settings.templateIds.value) {
            $Template = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'AppApprovalTemplate' and RowKey eq '$TemplateId'"
            if ($Template) {
                $TemplateData = $Template.JSON | ConvertFrom-Json
                $AppType = $TemplateData.AppType ?? 'EnterpriseApp'

                $IsAppMissing = $false
                if ($AppType -eq 'ApplicationManifest') {
                    # For Application Manifests, check by display name
                    $IsAppMissing = $TemplateData.AppName -notin $AppExists.displayName
                } elseif ($AppType -eq 'GalleryTemplate') {
                    # For Gallery Templates, check by application template ID
                    $IsAppMissing = $TemplateData.GalleryTemplateId -notin $AppExists.applicationTemplateId
                } else {
                    # For Enterprise Apps, check by app ID
                    $IsAppMissing = $TemplateData.AppId -notin $AppExists.appId
                }

                if ($IsAppMissing) {
                    $MissingApps.Add($TemplateData.AppName ?? $TemplateData.AppId ?? $TemplateData.GalleryTemplateId)
                }
            }
        }
    } else {
        # For copy mode, check by app ID as before
        $MissingApps = foreach ($App in $AppsToAdd) {
            if ($App -notin $AppExists.appId -and $App -notin $AppExists.applicationTemplateId) {
                $App
            }
        }
    }
    if ($Settings.remediate -eq $true) {
        if ($Mode -eq 'copy') {
            foreach ($App in $AppsToAdd) {
                $App = $App.Trim()
                if (!$App) {
                    continue
                }
                $Application = $AppExists | Where-Object -Property appId -EQ $App
                try {
                    New-CIPPApplicationCopy -App $App -Tenant $Tenant
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Added application $($Application.displayName) ($App) to $Tenant and updated it's permissions" -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to add app $($Application.displayName) ($App). Error: $ErrorMessage" -sev Error
                }
            }
        } elseif ($Mode -eq 'template') {
            $TemplateIds = $Settings.templateIds.value

            # Get template data to determine deployment type for each template
            $Table = Get-CIPPTable -TableName 'templates'

            foreach ($TemplateId in $TemplateIds) {
                try {
                    # Get the template data to determine if it's a Gallery Template or Enterprise App
                    $Template = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'AppApprovalTemplate' and RowKey eq '$TemplateId'"

                    if (!$Template) {
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Template $TemplateId not found" -sev Error
                        continue
                    }

                    $TemplateData = $Template.JSON | ConvertFrom-Json
                    # Default to EnterpriseApp for backward compatibility with older templates
                    $AppType = $TemplateData.AppType
                    if (-not $AppType) {
                        $AppType = 'EnterpriseApp'
                    }

                    if ($AppType -eq 'GalleryTemplate') {
                        # Handle Gallery Template deployment
                        Write-Information "Deploying Gallery Template $($TemplateData.AppName) to tenant $Tenant."

                        $GalleryTemplateId = $TemplateData.GalleryTemplateId
                        if (!$GalleryTemplateId) {
                            Write-LogMessage -API 'Standards' -tenant $tenant -message "Gallery Template ID not found in template data for $($TemplateData.TemplateName)" -sev Error
                            continue
                        }

                        # Check if the app already exists in the tenant
                        if ($TemplateData.GalleryTemplateId -in $AppExists.applicationTemplateId) {
                            Write-LogMessage -API 'Standards' -tenant $tenant -message "Gallery Template app $($TemplateData.AppName) already exists in tenant $Tenant" -sev Info
                            continue
                        }

                        # Instantiate the gallery template
                        $InstantiateBody = @{
                            displayName = $TemplateData.AppName
                        } | ConvertTo-Json -Depth 10

                        $InstantiateResult = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/applicationTemplates/$GalleryTemplateId/instantiate" -type POST -tenantid $Tenant -body $InstantiateBody

                        if ($InstantiateResult.application.appId) {
                            Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully deployed Gallery Template $($TemplateData.AppName) to tenant $Tenant. Application ID: $($InstantiateResult.application.appId)" -sev Info
                            New-CIPPApplicationCopy -App $InstantiateResult.application.appId -Tenant $Tenant
                        } else {
                            Write-LogMessage -API 'Standards' -tenant $tenant -message "Gallery Template deployment completed but application ID not returned for $($TemplateData.AppName) in tenant $Tenant" -sev Warning
                        }

                    } elseif ($AppType -eq 'ApplicationManifest') {
                        # Handle Application Manifest deployment
                        Write-Information "Deploying Application Manifest $($TemplateData.AppName) to tenant $Tenant."

                        $ApplicationManifest = $TemplateData.ApplicationManifest
                        if (!$ApplicationManifest) {
                            Write-LogMessage -API 'Standards' -tenant $tenant -message "Application Manifest not found in template data for $($TemplateData.TemplateName)" -sev Error
                            continue
                        }

                        # Check if an application with the same display name already exists
                        $ExistingApp = $AppExists | Where-Object { $_.displayName -eq $TemplateData.AppName }
                        if ($ExistingApp) {
                            Write-LogMessage -API 'Standards' -tenant $tenant -message "Application with name '$($TemplateData.AppName)' already exists in tenant $Tenant" -sev Info

                            # get existing application
                            $App = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/applications(appId='$($ExistingApp.appId)')" -tenantid $Tenant

                            # compare permissions
                            $ExistingPermissions = $App.requiredResourceAccess | ConvertTo-Json -Depth 10
                            $NewPermissions = $ApplicationManifest.requiredResourceAccess | ConvertTo-Json -Depth 10
                            if ($ExistingPermissions -ne $NewPermissions) {
                                Write-LogMessage -API 'Standards' -tenant $tenant -message "Updating permissions for existing application '$($TemplateData.AppName)' in tenant $Tenant" -sev Info

                                # Update permissions for existing application
                                $UpdateBody = @{
                                    requiredResourceAccess = $ApplicationManifest.requiredResourceAccess
                                } | ConvertTo-Json -Depth 10
                                $null = New-GraphPostRequest -type PATCH -uri "https://graph.microsoft.com/beta/applications(appId='$($ExistingApp.appId)')" -tenantid $Tenant -body $UpdateBody

                                # consent new permissions
                                Add-CIPPDelegatedPermission -RequiredResourceAccess $ApplicationManifest.requiredResourceAccess -ApplicationId $ExistingApp.appId -Tenantfilter $Tenant
                                Add-CIPPApplicationPermission -RequiredResourceAccess $ApplicationManifest.requiredResourceAccess -ApplicationId $ExistingApp.appId -Tenantfilter $Tenant
                            }

                            continue
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
                            $CreatedApp = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/applications' -type POST -tenantid $Tenant -body $CreateBody

                            if ($CreatedApp.appId) {
                                # Create service principal for the application
                                $ServicePrincipalBody = @{
                                    appId = $CreatedApp.appId
                                } | ConvertTo-Json

                                $ServicePrincipal = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/servicePrincipals' -type POST -tenantid $Tenant -body $ServicePrincipalBody

                                Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully deployed Application Manifest $($TemplateData.AppName) to tenant $Tenant. Application ID: $($CreatedApp.appId)" -sev Info

                                if ($CreatedApp.requiredResourceAccess) {
                                    Add-CIPPDelegatedPermission -RequiredResourceAccess $CreatedApp.requiredResourceAccess -ApplicationId $CreatedApp.appId -Tenantfilter $Tenant
                                    Add-CIPPApplicationPermission -RequiredResourceAccess $CreatedApp.requiredResourceAccess -ApplicationId $CreatedApp.appId -Tenantfilter $Tenant
                                }
                            } else {
                                Write-LogMessage -API 'Standards' -tenant $tenant -message "Application Manifest deployment failed - no application ID returned for $($TemplateData.AppName) in tenant $Tenant" -sev Error
                            }
                        } catch {
                            Write-LogMessage -API 'Standards' -tenant $tenant -message "Error creating application from manifest in tenant $Tenant - $($_.Exception.Message)" -sev Error
                        }

                    } else {
                        # Handle Enterprise App deployment (existing logic)
                        $AppId = $TemplateData.AppId
                        if ($AppId -notin $AppExists.appId) {
                            Write-Information "Adding $AppId to tenant $Tenant."
                            $PostResults = New-GraphPostRequest 'https://graph.microsoft.com/beta/servicePrincipals' -type POST -tenantid $Tenant -body "{ `"appId`": `"$AppId`" }"
                            Write-LogMessage -message "Added $AppId to tenant $Tenant" -tenant $Tenant -API 'Standards' -sev Info
                        }

                        # Apply permissions for Enterprise Apps
                        Add-CIPPApplicationPermission -TemplateId $TemplateId -TenantFilter $Tenant
                        Add-CIPPDelegatedPermission -TemplateId $TemplateId -TenantFilter $Tenant
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Added application $($TemplateData.AppName) from Enterprise App template and updated its permissions" -sev Info
                    }

                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to deploy template $TemplateId. Error: $ErrorMessage" -sev Error
                }
            }
        }
    }

    if ($Settings.alert) {
        if ($MissingApps.Count -gt 0) {
            Write-StandardsAlert -message "The following applications are not deployed: $($MissingApps -join ', ')" -object (@{ 'Missing Apps' = $MissingApps -join ',' }) -tenant $Tenant -standardName 'AppDeploy' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The following applications are not deployed: $($MissingApps -join ', ')" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'All applications are deployed' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $StateIsCorrect = $MissingApps.Count -eq 0 ? $true : @{ 'Missing Apps' = $MissingApps -join ',' }
        Set-CIPPStandardsCompareField -FieldName 'standards.AppDeploy' -FieldValue $StateIsCorrect -TenantFilter $tenant
        Add-CIPPBPAField -FieldName 'AppDeploy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

}
