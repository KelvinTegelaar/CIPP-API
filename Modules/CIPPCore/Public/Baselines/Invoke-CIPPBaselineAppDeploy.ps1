function Invoke-CIPPBaselineAppDeploy {
    <#
    .SYNOPSIS
        AppDeploy executor: deploys the configured applications to the tenant.
    .DESCRIPTION
        The classic's write. Copy mode: New-CIPPApplicationCopy per app id, permissions
        copied from the source. Template mode: each App Approval template deploys by type -
        gallery templates instantiate then copy permissions, application manifests create the
        app+SP and consent the manifest's permissions (or reconcile permissions on an
        existing same-name app), enterprise apps create the SP and apply the template's
        permissions. Per-app failures log and continue, as the classic continued.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $ServicePrincipals = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ServicePrincipals')
    $Mode = [string]($Remediate.mode.value ?? $Remediate.mode ?? 'copy')

    if ($Mode -eq 'copy') {
        foreach ($App in @("$($Remediate.appids)" -split ',')) {
            $App = $App.Trim()
            if (-not $App) { continue }
            $Application = $ServicePrincipals | Where-Object -Property appId -EQ $App
            try {
                New-CIPPApplicationCopy -App $App -Tenant $TenantFilter
                Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Added application $($Application.displayName) ($App) and updated its permissions." -Sev 'Info'
            } catch {
                Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Failed to add app $($Application.displayName) ($App): $($_.Exception.Message)" -Sev 'Error'
            }
        }
        return
    }

    $TemplateIds = @($Remediate.templateIds | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { $_ })
    $Table = Get-CIPPTable -TableName 'templates'
    foreach ($TemplateId in $TemplateIds) {
        try {
            $Template = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'AppApprovalTemplate' and RowKey eq '$TemplateId'"
            if (-not $Template) {
                Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "App approval template $TemplateId was not found." -Sev 'Error'
                continue
            }
            $TemplateData = $Template.JSON | ConvertFrom-Json
            $AppType = "$($TemplateData.AppType ?? 'EnterpriseApp')"

            if ($AppType -eq 'GalleryTemplate') {
                $GalleryTemplateId = "$($TemplateData.GalleryTemplateId)"
                if (-not $GalleryTemplateId) {
                    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Gallery template id missing on template $($TemplateData.TemplateName)." -Sev 'Error'
                    continue
                }
                if ($GalleryTemplateId -in @($ServicePrincipals.applicationTemplateId)) {
                    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Gallery template app $($TemplateData.AppName) already exists." -Sev 'Info'
                    continue
                }
                $InstantiateBody = @{ displayName = "$($TemplateData.AppName)" } | ConvertTo-Json -Depth 10
                $InstantiateResult = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/applicationTemplates/$GalleryTemplateId/instantiate" -type POST -tenantid $TenantFilter -body $InstantiateBody
                if ("$($InstantiateResult.application.appId)") {
                    New-CIPPApplicationCopy -App $InstantiateResult.application.appId -Tenant $TenantFilter
                    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Deployed gallery template $($TemplateData.AppName) as $($InstantiateResult.application.appId)." -Sev 'Info'
                } else {
                    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Gallery template deployment returned no application id for $($TemplateData.AppName)." -Sev 'Warning'
                }
            } elseif ($AppType -eq 'ApplicationManifest') {
                $ApplicationManifest = $TemplateData.ApplicationManifest
                if (-not $ApplicationManifest) {
                    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Application manifest missing on template $($TemplateData.TemplateName)." -Sev 'Error'
                    continue
                }
                $ExistingApp = $ServicePrincipals | Where-Object { "$($_.displayName)" -eq "$($TemplateData.AppName)" } | Select-Object -First 1
                if ($ExistingApp) {
                    # Same-name app: reconcile permissions instead of creating a duplicate.
                    $App = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/applications(appId='$($ExistingApp.appId)')" -tenantid $TenantFilter
                    $ExistingPermissions = $App.requiredResourceAccess | ConvertTo-Json -Depth 10
                    $NewPermissions = $ApplicationManifest.requiredResourceAccess | ConvertTo-Json -Depth 10
                    if ($ExistingPermissions -ne $NewPermissions) {
                        $UpdateBody = @{ requiredResourceAccess = $ApplicationManifest.requiredResourceAccess } | ConvertTo-Json -Depth 10
                        $null = New-GraphPostRequest -type PATCH -uri "https://graph.microsoft.com/beta/applications(appId='$($ExistingApp.appId)')" -tenantid $TenantFilter -body $UpdateBody
                        Add-CIPPDelegatedPermission -RequiredResourceAccess $ApplicationManifest.requiredResourceAccess -ApplicationId $ExistingApp.appId -Tenantfilter $TenantFilter
                        Add-CIPPApplicationPermission -RequiredResourceAccess $ApplicationManifest.requiredResourceAccess -ApplicationId $ExistingApp.appId -Tenantfilter $TenantFilter
                        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Updated permissions for the existing application '$($TemplateData.AppName)'." -Sev 'Info'
                    }
                    continue
                }
                $CleanManifest = $ApplicationManifest | ConvertTo-Json -Depth 10 | ConvertFrom-Json
                foreach ($Property in @('appId', 'id', 'createdDateTime', 'deletedDateTime', 'createdByAppId', 'publisherDomain', 'servicePrincipalLockConfiguration', 'identifierUris', 'applicationIdUris')) {
                    $CleanManifest.PSObject.Properties.Remove($Property)
                }
                $CreatedApp = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/applications' -type POST -tenantid $TenantFilter -body ($CleanManifest | ConvertTo-Json -Depth 10)
                if ("$($CreatedApp.appId)") {
                    $null = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/servicePrincipals' -type POST -tenantid $TenantFilter -body (@{ appId = $CreatedApp.appId } | ConvertTo-Json)
                    if ($CreatedApp.requiredResourceAccess) {
                        Add-CIPPDelegatedPermission -RequiredResourceAccess $CreatedApp.requiredResourceAccess -ApplicationId $CreatedApp.appId -Tenantfilter $TenantFilter
                        Add-CIPPApplicationPermission -RequiredResourceAccess $CreatedApp.requiredResourceAccess -ApplicationId $CreatedApp.appId -Tenantfilter $TenantFilter
                    }
                    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Deployed application manifest $($TemplateData.AppName) as $($CreatedApp.appId)." -Sev 'Info'
                } else {
                    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Application manifest deployment returned no application id for $($TemplateData.AppName)." -Sev 'Error'
                }
            } else {
                $AppId = "$($TemplateData.AppId)"
                if ($AppId -notin @($ServicePrincipals.appId)) {
                    $null = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/servicePrincipals' -type POST -tenantid $TenantFilter -body "{ `"appId`": `"$AppId`" }"
                }
                Add-CIPPApplicationPermission -TemplateId $TemplateId -TenantFilter $TenantFilter
                Add-CIPPDelegatedPermission -TemplateId $TemplateId -TenantFilter $TenantFilter
                Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Added application $($TemplateData.AppName) from the enterprise app template and updated its permissions." -Sev 'Info'
            }
        } catch {
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Failed to deploy template ${TemplateId}: $($_.Exception.Message)" -Sev 'Error'
        }
    }
}
