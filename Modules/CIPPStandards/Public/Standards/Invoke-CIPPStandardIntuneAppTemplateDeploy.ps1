function Invoke-CIPPStandardIntuneAppTemplateDeploy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) IntuneAppTemplateDeploy
    .SYNOPSIS
        (Label) Deploy Intune Application Template
    .DESCRIPTION
        (Helptext) Deploys selected Intune application templates to the tenant. Supports WinGet/Store apps, Office apps, Chocolatey apps, Win32 script apps, and MSP apps.
        (DocsDescription) Uses CIPP Intune Application Templates to deploy applications across tenants as a standard. Each template can contain multiple applications of different types which will be queued for deployment.
    .NOTES
        CAT
            Intune Standards
        TAG
        EXECUTIVETEXT
            Automatically deploys approved Intune applications across all managed tenants, ensuring consistent software availability and reducing manual deployment overhead. Supports WinGet, Office, Chocolatey, Win32, and MSP application types.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":true,"creatable":false,"label":"Select Application Templates","name":"standards.IntuneAppTemplateDeploy.templateIds","api":{"url":"/api/ListAppTemplates","labelField":"Displayname","valueField":"GUID","queryKey":"StdIntuneAppTemplateList"}}
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-05-23
        POWERSHELLEQUIVALENT
            Graph API - /deviceAppManagement/mobileApps
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param(
        $Tenant,
        $Settings
    )

    $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneAppTemplateDeploy' -TenantFilter $Tenant -Preset Intune
    if ($TestResult -eq $false) { return $true }

    $TemplateIds = @($Settings.templateIds.value ?? $Settings.templateIds)
    if ($TemplateIds.Count -eq 0) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'IntuneAppTemplateDeploy: No template IDs provided, skipping.' -sev Error
        return
    }

    # Get current Intune apps via live Graph call (same as Push-UploadApplication)
    $BaseUri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'
    $CurrentApps = @(New-GraphGetRequest -Uri $BaseUri -tenantid $Tenant)

    # Load all selected templates and build per-app objects
    $Table = Get-CIPPTable -TableName 'templates'
    $MissingApps = [System.Collections.Generic.List[PSCustomObject]]::new()
    $CurrentAppNames = @($CurrentApps.displayName)

    foreach ($TemplateId in $TemplateIds) {
        $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'AppTemplate' and RowKey eq '$TemplateId'"
        if (-not $Entity) { continue }

        $TemplateData = $Entity.JSON | ConvertFrom-Json -Depth 100
        $TemplateName = $TemplateData.Displayname
        $AppsRaw = $TemplateData.Apps

        # Build individual app objects from the template apps collection
        $AppTypes = @($AppsRaw.appType)
        $AppNames = @($AppsRaw.appName)
        $AppConfigs = @($AppsRaw.config)

        for ($i = 0; $i -lt $AppTypes.Count; $i++) {
            $RawConfig = $AppConfigs[$i]
            $Config = if ($RawConfig -is [string]) { $RawConfig | ConvertFrom-Json -Depth 100 } else { $RawConfig }
            $DisplayName = [string]($Config.ApplicationName ?? $Config.displayName ?? $AppNames[$i])

            if ($DisplayName -notin $CurrentAppNames) {
                $MissingApps.Add([PSCustomObject]@{
                    TemplateId   = [string]$TemplateId
                    TemplateName = [string]$TemplateName
                    AppName      = [string]$DisplayName
                    AppType      = [string]$AppTypes[$i]
                    Config       = $Config
                })
            }
        }
    }

    $ExpectedValue = [PSCustomObject]@{ state = 'All template apps deployed' }
    $CurrentValue = if ($MissingApps.Count -eq 0) {
        [PSCustomObject]@{ state = 'All template apps deployed' }
    } else {
        [PSCustomObject]@{ MissingApps = ($MissingApps.AppName -join ', ') }
    }

    if ($Settings.remediate -eq $true) {
        if ($MissingApps.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All Intune application template apps are already deployed.' -sev Info
        } else {
            foreach ($App in $MissingApps) {
                try {
                    # Map template appType to queue type used by New-CIPPIntuneAppDeployment
                    $QueueType = switch ($App.AppType) {
                        'StoreApp'       { 'WinGet' }
                        'chocolateyApp'  { 'Choco' }
                        'win32ScriptApp' { 'Win32ScriptApp' }
                        'mspApp'         { 'MSPApp' }
                        'officeApp'      { 'OfficeApp' }
                        default          { $App.AppType }
                    }

                    # Build AppConfig in the same format as the apps queue
                    # Assignment info comes from the template's per-app config
                    $DeployConfig = $App.Config | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
                    $DeployConfig | Add-Member -NotePropertyName 'type' -NotePropertyValue $QueueType -Force
                    $DeployConfig | Add-Member -NotePropertyName 'Applicationname' -NotePropertyValue $App.AppName -Force
                    # Compute assignTo the same way the HTTP handlers do
                    $AppAssignTo = if ($DeployConfig.AssignTo -eq 'customGroup') { $DeployConfig.CustomGroup } else { $DeployConfig.AssignTo }
                    $DeployConfig | Add-Member -NotePropertyName 'assignTo' -NotePropertyValue $AppAssignTo -Force

                    $null = New-CIPPIntuneAppDeployment -AppConfig $DeployConfig -TenantFilter $Tenant -APIName 'Standards'
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Deployed Intune app '$($App.AppName)' ($($App.AppType)) from template '$($App.TemplateName)'." -sev Info
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to deploy Intune app '$($App.AppName)' from template '$($App.TemplateName)': $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                }
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($MissingApps.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All Intune application template apps are deployed.' -sev Info
        } else {
            $MissingList = $MissingApps.AppName -join ', '
            Write-StandardsAlert -message "The following Intune template apps are not deployed: $MissingList" -object (@{ 'Missing Apps' = $MissingList }) -tenant $Tenant -standardName 'IntuneAppTemplateDeploy' -standardId $Settings.standardId
        }
    }

    if ($Settings.report -eq $true) {
        $StateIsCorrect = $MissingApps.Count -eq 0
        Set-CIPPStandardsCompareField -FieldName 'standards.IntuneAppTemplateDeploy' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'IntuneAppTemplateDeploy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
