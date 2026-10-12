function Get-CIPPBaselineIntuneAppTemplateDeployState {
    <#
    .SYNOPSIS
        Prepare hook for IntuneAppTemplateDeploy: presence of the configured template apps.
    .DESCRIPTION
        Resolves each configured App Template to its per-app list and grades an empty
        missing-apps set against the IntuneMobileApps cache. Office is a singleton Graph
        always names 'Microsoft 365 Apps for Windows 10 and later' regardless of the
        template's name, so it is tracked by @odata.type instead - the classic's rule.
        The full missing-app objects (type + config) are carried for the executor's queue.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Apps = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'IntuneMobileApps')
    if ($Apps.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'IntuneMobileApps')) {
        return @{ Current = $null }
    }

    $TemplateIds = @($Item.Variables.templateIds | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { $_ })
    if ($TemplateIds.Count -eq 0) { return @{ Current = $null } }

    $CurrentAppNames = @($Apps | ForEach-Object { "$($_.displayName)" })
    $OfficeDeployed = @($Apps | Where-Object { "$($_.'@odata.type')" -eq '#microsoft.graph.officeSuiteApp' }).Count -gt 0

    $Table = Get-CIPPTable -TableName 'templates'
    $MissingApps = [System.Collections.Generic.List[object]]::new()
    foreach ($TemplateId in $TemplateIds) {
        $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'AppTemplate' and RowKey eq '$TemplateId'"
        if (-not $Entity) { continue }
        $TemplateData = $Entity.JSON | ConvertFrom-Json -Depth 100
        $AppTypes = @($TemplateData.Apps.appType)
        $AppNames = @($TemplateData.Apps.appName)
        $AppConfigs = @($TemplateData.Apps.config)
        for ($i = 0; $i -lt $AppTypes.Count; $i++) {
            $RawConfig = $AppConfigs[$i]
            $Config = if ($RawConfig -is [string]) { $RawConfig | ConvertFrom-CippAppConfig } else { $RawConfig }
            $AppType = [string]$AppTypes[$i]
            $DisplayName = [string]($Config.ApplicationName ?? $Config.displayName ?? $AppNames[$i])
            if ([string]::IsNullOrWhiteSpace($DisplayName)) {
                # A nameless app cannot be created in Intune and cannot be matched against
                # deployed apps - broken template data, skipped with a log instead of an
                # unnameable missing-app row and a doomed deploy.
                Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "App template '$($TemplateData.Displayname)' contains an app with no name (type $AppType) - skipped. Fix the template." -Sev 'Warning'
                continue
            }
            $IsDeployed = if ($AppType -eq 'officeApp') { $OfficeDeployed } else { $DisplayName -in $CurrentAppNames }
            if (-not $IsDeployed) {
                $MissingApps.Add([PSCustomObject]@{
                        TemplateId   = "$TemplateId"
                        TemplateName = "$($TemplateData.Displayname)"
                        AppName      = $DisplayName
                        AppType      = $AppType
                        Config       = $Config
                    })
            }
        }
    }

    $Current = [PSCustomObject]@{
        missingApps = @($MissingApps | ForEach-Object { "$($_.AppName)" } | Sort-Object)
    }
    # Carried for the executor.
    $Current | Add-Member -NotePropertyName 'missingAppObjects' -NotePropertyValue @($MissingApps)

    @{
        Expected = [PSCustomObject]@{ missingApps = @() }
        Current  = $Current
    }
}
