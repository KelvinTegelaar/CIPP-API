function Invoke-ExecGetBaselineWhatIfReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Baselines.Read
    .DESCRIPTION
        Server-renders the Security Baseline report for a tenant as application/pdf bytes: where the
        assigned baselines stand today, what is already in place, the Conditional Access and Intune
        policies and the settings the baseline will change (what each does, its value today, the value
        it will be set to and why), the rollout waves still to come and the agreed exceptions - plus,
        optionally, everything one or more simulated (not yet assigned) baselines would add. Reads the
        same alignment, baseline and catalog data the Baselines page shows, composes it through the
        shared CIPPSharp component kit (Build-CippBaselineWhatIfReportTree) and returns the finished
        PDF. Nothing is changed by producing it.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -Headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        # Required. The tenant (default domain) to report on.
        $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'A tenantFilter is required' })
        }

        # Optional. Show the "What Is Already In Place" page (deployed policies and enforced settings,
        # with their values). A boolean; defaults to true.
        $AlreadyAligned = $Request.Body.sectionConfig.alreadyAligned
        # Optional. Show the "How The Rollout Works" section (the remaining waves and when they
        # arrive). A boolean; defaults to true.
        $RolloutStages = $Request.Body.sectionConfig.rolloutStages
        # Only a real boolean is accepted: a string would read as true ([bool]'false' is $true).
        if ($null -ne $AlreadyAligned -and $AlreadyAligned -isnot [bool]) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'sectionConfig.alreadyAligned must be true or false.' })
        }
        if ($null -ne $RolloutStages -and $RolloutStages -isnot [bool]) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'sectionConfig.rolloutStages must be true or false.' })
        }

        # Optional. The GUIDs of baselines NOT assigned to the tenant, whose additions are shown in the
        # report as planned changes, in the order given; a repeated id counts once. Ids of assigned
        # baselines are ignored.
        $SimulatedTemplateIds = [System.Collections.Generic.List[string]]::new()
        foreach ($Id in $Request.Body.simulatedTemplateIds) {
            if (-not [string]::IsNullOrWhiteSpace([string]$Id) -and -not $SimulatedTemplateIds.Contains([string]$Id)) { $SimulatedTemplateIds.Add([string]$Id) }
        }

        # Optional. The branding preset to render with; an unknown id falls back to the default branding.
        $BrandingPresetId = [string]($Request.Body.brandingPresetId ?? $Request.Query.brandingPresetId)

        $Alignment = Get-CIPPBaselineAlignment -TenantFilter $TenantFilter
        $Rows = @($Alignment.rows | Where-Object { $null -ne $_ })
        $StageStates = @($Alignment.stageStates | Where-Object { $null -ne $_ })
        # -ResolveIdentityLabels turns CA/Intune template variables into {label, value}: the label is
        # what names a policy whose stored template is gone.
        $Baselines = @(Get-CIPPBaseline -ResolveIdentityLabels)
        $AssignedIds = @($StageStates.templateId)
        $AssignedTemplates = @($Baselines | Where-Object { $AssignedIds -contains $_.GUID })
        $SimulatedTemplates = [System.Collections.Generic.List[object]]::new()
        foreach ($Id in $SimulatedTemplateIds) {
            if ($AssignedIds -contains $Id) { continue }
            $Baseline = $Baselines | Where-Object { $_.GUID -eq $Id } | Select-Object -First 1
            if (-not $Baseline) {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = "Unknown baseline id '$Id'." })
            }
            $SimulatedTemplates.Add($Baseline)
        }

        # Stored CA/Intune templates keyed by template id: standards not checked yet and simulated
        # baselines carry only the template id, so the stored template supplies the policy content.
        # Ordinal, as the client's lookup objects are: an @{} literal would match an id of another case.
        $CaByGuid = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        $IntuneByGuid = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        if (@($Rows | Where-Object { $_.status -eq 'No Data' }).Count -gt 0 -or $SimulatedTemplates.Count -gt 0) {
            $TemplatesTable = Get-CippTable -tablename 'templates'
            foreach ($Template in @(Get-CIPPAzDataTableEntity @TemplatesTable -Filter "PartitionKey eq 'CATemplate'")) {
                try {
                    $Content = $Template.JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop
                    $CaByGuid["$($Template.RowKey)"] = $Content
                    if ($Template.GUID) { $CaByGuid["$($Template.GUID)"] = $Content }
                } catch {
                    Write-Information "Baseline report: skipped unreadable CA template $($Template.RowKey): $($_.Exception.Message)"
                }
            }
            foreach ($Template in @(Get-CIPPAzDataTableEntity @TemplatesTable -Filter "PartitionKey eq 'IntuneTemplate'")) {
                try {
                    # Stored Intune templates name the policy in 'Displayname'.
                    $IntuneByGuid["$($Template.RowKey)"] = @{ displayName = ($Template.JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop).Displayname }
                } catch {
                    Write-Information "Baseline report: skipped unreadable Intune template $($Template.RowKey): $($_.Exception.Message)"
                }
            }
        }

        $TenantName = Get-CippReportTenantName -TenantFilter $TenantFilter -BrandingPresetId $BrandingPresetId
        $Report = Build-CippBaselineWhatIfReportTree -Data @{
            TenantName         = $TenantName
            tenant             = @{ rows = $Rows }
            stageStates        = $StageStates
            assignedTemplates  = $AssignedTemplates
            simulatedTemplates = @($SimulatedTemplates)
            catalog            = @(Get-CIPPBaselineDefinition)
            resolvers          = @{ caByGuid = $CaByGuid; intuneByGuid = $IntuneByGuid }
            sectionConfig      = @{ alreadyAligned = ($AlreadyAligned ?? $true); rolloutStages = ($RolloutStages ?? $true) }
        }

        $Bytes = ConvertTo-CippReportPdf -Blocks $Report.Blocks -Variables $Report.Variables -TenantName $TenantName -TenantFilter $TenantFilter `
            -ReportName 'Security Baseline Report' -BrandingPresetId $BrandingPresetId
        $FileName = ("Baseline_Report_$TenantFilter" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -message "Failed to render the Security Baseline report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
