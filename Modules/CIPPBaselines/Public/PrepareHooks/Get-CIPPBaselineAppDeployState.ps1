function Get-CIPPBaselineAppDeployState {
    <#
    .SYNOPSIS
        Prepare hook for AppDeploy: presence of the configured applications.
    .DESCRIPTION
        Grades an empty missing-apps list against the ServicePrincipals cache, the classic's
        exact check. Copy mode checks the configured app ids against appId and
        applicationTemplateId; template mode resolves each App Approval template to its
        type-specific identity - display name for manifests, gallery template id for gallery
        apps, app id for enterprise apps.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $ServicePrincipals = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ServicePrincipals')
    if ($ServicePrincipals.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ServicePrincipals')) {
        return @{ Current = $null }
    }

    $V = $Item.Variables
    $Mode = [string]($V.mode.value ?? $V.mode ?? 'copy')
    $MissingApps = [System.Collections.Generic.List[string]]::new()

    if ($Mode -eq 'template') {
        $TemplateIds = @($V.templateIds | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { $_ })
        if ($TemplateIds.Count -eq 0) { return @{ Current = $null } }
        $Table = Get-CIPPTable -TableName 'templates'
        foreach ($TemplateId in $TemplateIds) {
            $Template = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'AppApprovalTemplate' and RowKey eq '$TemplateId'"
            if (-not $Template) { continue }
            $TemplateData = $Template.JSON | ConvertFrom-Json
            $AppType = "$($TemplateData.AppType ?? 'EnterpriseApp')"
            $IsAppMissing = switch ($AppType) {
                'ApplicationManifest' { "$($TemplateData.AppName)" -notin @($ServicePrincipals.displayName) }
                'GalleryTemplate' { "$($TemplateData.GalleryTemplateId)" -notin @($ServicePrincipals.applicationTemplateId) }
                default { "$($TemplateData.AppId)" -notin @($ServicePrincipals.appId) }
            }
            if ($IsAppMissing) {
                $MissingApps.Add("$($TemplateData.AppName ?? $TemplateData.AppId ?? $TemplateData.GalleryTemplateId)")
            }
        }
    } else {
        $AppsToAdd = @("$($V.appids)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($AppsToAdd.Count -eq 0) { return @{ Current = $null } }
        foreach ($App in $AppsToAdd) {
            if ($App -notin @($ServicePrincipals.appId) -and $App -notin @($ServicePrincipals.applicationTemplateId)) {
                $MissingApps.Add($App)
            }
        }
    }

    @{
        Expected = [PSCustomObject]@{ missingApps = @() }
        Current  = [PSCustomObject]@{ missingApps = @($MissingApps | Sort-Object) }
    }
}
