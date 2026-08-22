function Invoke-CIPPBaselineMigration {
    <#
    .SYNOPSIS
        Migrates classic StandardsTemplateV2 templates (standards + drift) into baselines.
    .DESCRIPTION
        Reads every 'templates' row under PK StandardsTemplateV2 and converts each into a
        one-stage ('Default') baseline via New-CIPPBaseline. -Preview builds the full
        per-template report without writing anything; commit mode writes and reports what
        happened. The V2 rows are never touched - both systems run side by side until the
        operator retires V2.

        Mapping rules:
        - tenantFilter/excludedTenants selector objects carry over verbatim.
        - Settings live at entry.standards.<Name> (V2's double nesting) or on the entry
          itself for template-array standards; {label,value} options unwrap to .value;
          values coerce to the V3 variable's declared type; keys match variables
          case-insensitively (V2 loved PascalCase where V3 uses camelCase).
        - Posture: remediate = action contains Remediate or autoRemediate; alert = action
          contains warn. Drift templates force report+alert (drift IS detect-and-triage).
          -ReportOnly (the default) forces remediation off everywhere and reports the
          faithful posture per standard so the operator re-enables deliberately.
        - Multi-instance arrays (IntuneTemplate/ConditionalAccessTemplate/Quarantine...)
          become one instance each, keyed by a stable hash of the referenced template id
          so re-migration updates instead of duplicating. 'TemplateList-Tags' selections
          map to the IntuneTemplatePackage standard (tag = package, membership stays live).
        - A hand-authored specials map covers the renamed/restructured standards; any key
          that still cannot be mapped lands in the report as a warning and the V3 default
          applies - nothing drops silently.
        - Idempotency: Source 'StandardsTemplateV2:<v2 guid>' + SHA over the V2 JSON on
          the rollout row. Unchanged re-commits skip, changed ones update the SAME
          baseline GUID so triage and resolved rows survive.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [switch]$Preview,
        $TemplateIds,
        [bool]$ReportOnly = $true,
        [bool]$AddDetectStandards = $false,
        $User = 'Baseline Migration'
    )

    $Definitions = @(Get-CIPPBaselineDefinition)
    $DefinitionsByName = @{}
    foreach ($Definition in $Definitions) {
        if ("$($Definition.name)") { $DefinitionsByName["$($Definition.name)"] = $Definition }
    }

    # Per-standard translation of V2 keys/values that V3 renamed or restructured.
    # rename: V2 key -> V3 variable. value: V3 variable -> { V2 value -> V3 value }.
    # drop: V2 keys with no V3 equivalent - reported as warnings, defaults apply.
    $Specials = @{
        AutoArchive                   = @{ rename = @{ AutoArchivingThresholdPercentage = 'threshold' } }
        AutoArchiveMailbox            = @{ rename = @{ state = 'enabled' }; value = @{ enabled = @{ enabled = $true; disabled = $false } } }
        AutopilotStatusPage           = @{ drop = @('AllowRetry'); dropNotes = @{ AllowRetry = "a leftover from an old classic-standard version - the current classic standard ignores it too (the 'Block device usage during setup' switch drives the retry setting)" } }
        Bookings                      = @{ rename = @{ state = 'enabled' } }
        CloudMessageRecall            = @{ rename = @{ state = 'enabled' } }
        ConditionalAccessTemplate     = @{ rename = @{ TemplateList = 'caTemplate' }; value = @{ state = @{ Enabled = 'enabled'; Disabled = 'disabled' } } }
        DisableAddShortcutsToOneDrive = @{ rename = @{ state = 'disableAddToOneDrive' } }
        EnableMailTips                = @{ rename = @{ MailTipsLargeAudienceThreshold = 'largeAudienceThreshold' } }
        # V2's double negative: state 'enabled' = Direct Send allowed = reject OFF.
        EXODirectSend                 = @{ rename = @{ state = 'rejectDirectSend' }; value = @{ rejectDirectSend = @{ enabled = $false; disabled = $true } } }
        FocusedInbox                  = @{ rename = @{ state = 'enabled' } }
        SafeAttachmentPolicy          = @{ rename = @{ action = 'SafeAttachmentAction' } }
        # V2 stored the Graph string enum; the V3 definition speaks SPO numerics.
        sharingCapability             = @{ rename = @{ Level = 'sharingCapability' }; value = @{ sharingCapability = @{ disabled = 0; externalUserSharingOnly = 1; externalUserAndGuestSharing = 2; existingExternalUserSharingOnly = 3 } } }
        SpoofWarn                     = @{ rename = @{ state = 'externalWarningEnabled' }; value = @{ externalWarningEnabled = @{ enabled = $true; disabled = $false } } }
        SPSyncButtonState             = @{ rename = @{ state = 'hideSyncButton' } }
        TAP                           = @{ rename = @{ config = 'isUsableOnce' } }
        unmanagedSync                 = @{ rename = @{ state = 'conditionalAccessPolicy' } }
        BitLockerKeysForOwnedDevice   = @{ rename = @{ state = 'allowed' }; value = @{ allowed = @{ allow = $true; restrict = $false } } }
        TeamsExternalAccessPolicy     = @{ rename = @{ EnablePublicCloudAccess = 'EnableTeamsConsumerInbound' }; warnRename = $true }
        TeamsFederationConfiguration  = @{ rename = @{ AllowPublicUsers = 'AllowTeamsConsumerInbound' }; warnRename = $true }
    }

    $Unwrap = {
        param($Value)
        if ($Value -is [System.Management.Automation.PSCustomObject] -and $null -ne $Value.PSObject.Properties['value']) { $Value.value } else { $Value }
    }
    $Coerce = {
        param($Value, $Type)
        switch ("$Type") {
            'switch' { "$Value" -in @('True', 'true', '1') }
            'number' { $(try { [int64]"$Value" } catch { $Value }) }
            default { $Value }
        }
    }
    # Stable instance suffix so re-migration lands on the same instance keys.
    $InstanceId = {
        param($Seed)
        $Hash = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes("$Seed"))
        ([System.Convert]::ToHexString($Hash)).Substring(0, 8).ToLower()
    }

    # One V2 standard entry -> one V3 standardsConfig entry (or $null + warnings).
    $MapEntry = {
        param($Name, $Entry, $IsDrift)
        $Warnings = [System.Collections.Generic.List[string]]::new()

        # Actions -> posture. autoRemediate is a settings-level flag meaning the same.
        $Actions = @(@($Entry.action) | ForEach-Object { & $Unwrap $_ } | Where-Object { $_ })
        $Settings = [ordered]@{}
        $Nested = $Entry.standards.$Name
        if ($Nested -is [System.Management.Automation.PSCustomObject]) {
            foreach ($Property in $Nested.PSObject.Properties) { $Settings[$Property.Name] = $Property.Value }
        }
        foreach ($Property in $Entry.PSObject.Properties) {
            if ($Property.Name -in @('action', 'standards')) { continue }
            $Settings[$Property.Name] = $Property.Value
        }
        $Remediate = ($Actions -contains 'Remediate') -or ("$($Settings['autoRemediate'])" -eq 'True')
        $Alert = $Actions -contains 'warn'
        $null = $Settings.Remove('autoRemediate')
        # Drift templates are detect-and-triage: report + alert, never auto-fix.
        if ($IsDrift) { $Remediate = $false; $Alert = $true }
        $EffectiveRemediate = $(if ($ReportOnly) { $false } else { $Remediate })

        # Template selectors get their own routing before the generic key mapping.
        $TargetName = $Name
        $InstanceSeed = $null
        if ($Name -eq 'DeployContactTemplates') {
            # V2 stored a multi-select of contact templates on ONE entry; V3 is
            # multi-instance - one instance per template, keyed by its id.
            $ContactConfigs = [System.Collections.Generic.List[object]]::new()
            foreach ($TemplateRef in @($Settings['templateIds'])) {
                $ContactGuid = "$(& $Unwrap $TemplateRef)"
                if (-not $ContactGuid) { continue }
                $ContactConfigs.Add([PSCustomObject]@{
                        standard          = $Name
                        instance          = ('{0}#m{1}' -f $Name, (& $InstanceId "tpl:$ContactGuid"))
                        variables         = [PSCustomObject]@{ contactTemplate = $ContactGuid }
                        remediateEnabled  = $EffectiveRemediate
                        alertEnabled      = $Alert
                        alertOnRemediate  = $false
                        faithfulRemediate = $Remediate
                    })
            }
            if ($ContactConfigs.Count -eq 0) {
                $Warnings.Add('DeployContactTemplates selects no templates - skipped')
            }
            return [PSCustomObject]@{ Configs = @($ContactConfigs); Warnings = $Warnings }
        }
        if ($Name -eq 'IntuneTemplate') {
            # Some editors saved both selector keys with one of them null - clear the
            # empty one so it never reaches the generic mapper as noise.
            if (-not "$(& $Unwrap $Settings['TemplateList-Tags'])") { $null = $Settings.Remove('TemplateList-Tags') }
            if ($null -ne $Settings['TemplateList-Tags']) {
                # A tag selection is a package: membership stays live via the package
                # standard instead of V2's frozen snapshot.
                $TargetName = 'IntuneTemplatePackage'
                $Tag = & $Unwrap $Settings['TemplateList-Tags']
                $Settings['intuneTemplatePackage'] = "$Tag"
                $InstanceSeed = "tag:$Tag"
                $null = $Settings.Remove('TemplateList-Tags')
                $null = $Settings.Remove('TemplateList')
            } elseif ($null -ne $Settings['TemplateList']) {
                $TemplateGuid = & $Unwrap $Settings['TemplateList']
                $Settings['intuneTemplate'] = "$TemplateGuid"
                $InstanceSeed = "tpl:$TemplateGuid"
                $null = $Settings.Remove('TemplateList')
                $null = $Settings.Remove('TemplateList-Tags')
            } else {
                $Warnings.Add('IntuneTemplate entry selects no template - skipped')
                return [PSCustomObject]@{ Configs = @(); Warnings = $Warnings }
            }
        } elseif ($Name -eq 'ConditionalAccessTemplate') {
            $TemplateGuid = & $Unwrap $Settings['TemplateList']
            if (-not "$TemplateGuid") {
                $Warnings.Add('ConditionalAccessTemplate entry selects no template - skipped')
                return [PSCustomObject]@{ Configs = @(); Warnings = $Warnings }
            }
            $InstanceSeed = "tpl:$TemplateGuid"
        }

        $Definition = $DefinitionsByName[$TargetName]
        if (-not $Definition) {
            $Warnings.Add("$TargetName has no V3 definition - skipped")
            return [PSCustomObject]@{ Configs = @(); Warnings = $Warnings }
        }

        # Specials first (renames + value maps + documented drops), then the generic
        # case-insensitive key match against the definition's variables.
        $Special = $Specials[$Name]
        foreach ($Dropped in @($Special.drop | Where-Object { $_ })) {
            if ($null -ne $Settings[$Dropped]) {
                $DropNote = ($Special.dropNotes ?? @{})[$Dropped] ?? 'has no V3 equivalent'
                $Warnings.Add("'$Dropped' dropped - $DropNote (was '$(& $Unwrap $Settings[$Dropped])')")
                $null = $Settings.Remove($Dropped)
            }
        }
        foreach ($Rename in ($Special.rename ?? @{}).GetEnumerator()) {
            if ($null -ne $Settings[$Rename.Key]) {
                $Settings[$Rename.Value] = $Settings[$Rename.Key]
                $null = $Settings.Remove($Rename.Key)
                if ($Special.warnRename) { $Warnings.Add("'$($Rename.Key)' migrated to '$($Rename.Value)' - verify the semantics match your intent") }
            }
        }

        $DefVars = @($Definition.variables.PSObject.Properties)
        $Variables = [ordered]@{}
        foreach ($Key in @($Settings.Keys)) {
            $Value = & $Unwrap $Settings[$Key]
            $DefVar = $DefVars | Where-Object { $_.Name -eq $Key } | Select-Object -First 1
            if (-not $DefVar) {
                # V2 PascalCase vs V3 camelCase: same name, different casing.
                $DefVar = $DefVars | Where-Object { $_.Name -ieq $Key } | Select-Object -First 1
            }
            if (-not $DefVar) {
                $Warnings.Add("'$Key' does not map to a V3 variable - dropped (was '$Value'); the V3 default applies")
                continue
            }
            $ValueMap = ($Special.value ?? @{})[$DefVar.Name]
            if ($ValueMap -and $null -ne $ValueMap["$Value"]) { $Value = $ValueMap["$Value"] }
            # Snap to the definition's own option value so the TYPE matches what the
            # editor would store - V2 saved numeric enums as strings ('1' vs 1).
            $MatchingOption = @($DefVar.Value.options) | Where-Object { "$($_.value)" -eq "$Value" } | Select-Object -First 1
            if ($MatchingOption) { $Value = $MatchingOption.value }
            $Variables[$DefVar.Name] = & $Coerce $Value $DefVar.Value.type
        }

        $Instance = if ($InstanceSeed) {
            '{0}#m{1}' -f $TargetName, (& $InstanceId $InstanceSeed)
        } elseif ($Definition.multiple -eq $true) {
            # Seed from the identity variable when the definition declares one; the
            # whole variable set otherwise. Never index with a null key - that throws.
            $IdentityKey = "$($Definition.instanceIdentity)"
            $Seed = if ($IdentityKey -and $null -ne $Variables[$IdentityKey]) {
                "$($Variables[$IdentityKey])"
            } else {
                ConvertTo-Json -Compress -Depth 20 -InputObject $Variables
            }
            '{0}#m{1}' -f $TargetName, (& $InstanceId $Seed)
        } else { $TargetName }

        [PSCustomObject]@{
            Configs  = @([PSCustomObject]@{
                    standard          = $TargetName
                    instance          = $Instance
                    variables         = [PSCustomObject]$Variables
                    remediateEnabled  = $EffectiveRemediate
                    alertEnabled      = $Alert
                    alertOnRemediate  = $false
                    faithfulRemediate = $Remediate
                })
            Warnings = $Warnings
        }
    }

    $TemplateTable = Get-CippTable -tablename 'templates'
    $Rows = @(Get-CIPPAzDataTableEntity @TemplateTable -Filter "PartitionKey eq 'StandardsTemplateV2'")
    $RolloutTable = Get-CippTable -tablename 'BaselineRollouts'
    $Report = [System.Collections.Generic.List[object]]::new()

    foreach ($Row in $Rows) {
        $V2Guid = "$($Row.GUID ?? $Row.RowKey)"
        if ($TemplateIds -and $V2Guid -notin @($TemplateIds)) { continue }

        $Entry = [PSCustomObject]@{
            v2Guid         = $V2Guid
            templateName   = ''
            type           = 'standards'
            status         = 'Ready'
            detail         = ''
            tenants        = @()
            standardsCount = 0
            warnings       = @()
            standards      = @()
        }
        $Report.Add($Entry)

        $Json = $(try { $Row.JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop } catch { $null })
        if (-not $Json -or -not $Json.standards -or @($Json.standards.PSObject.Properties).Count -eq 0) {
            $Entry.status = 'Skipped'
            $Entry.detail = 'The template JSON is empty or unreadable - nothing to migrate.'
            $Entry.templateName = "$($Json.templateName)"
            continue
        }
        $Entry.templateName = "$($Json.templateName)"
        $IsDrift = ($Json.type -eq 'drift') -or ($Json.isDriftTemplate -eq $true)
        if ($IsDrift) { $Entry.type = 'drift' }
        $Warnings = [System.Collections.Generic.List[string]]::new()
        # V2 stamped repo-saved templates with the 'Template Tenant' placeholder. Map it
        # to the baselines' own display-only 'Exported Template' placeholder: it shows in
        # the editor so the operator re-assigns, but never becomes a runnable tenant.
        $Assignments = [System.Collections.Generic.List[object]]::new()
        $HadPlaceholder = $false
        foreach ($Assignment in @($Json.tenantFilter)) {
            if ($null -eq $Assignment) { continue }
            $AssignmentValue = if ($Assignment -is [string]) { $Assignment } else { "$($Assignment.value)" }
            if ($AssignmentValue -eq 'Template Tenant') {
                $HadPlaceholder = $true
                continue
            }
            $Assignments.Add($Assignment)
        }
        if ($HadPlaceholder -and $Assignments.Count -eq 0) {
            $Assignments.Add([PSCustomObject]@{ label = 'Exported Template'; value = 'Exported Template'; type = 'Tenant' })
            $Warnings.Add("The V2 template was assigned to the 'Template Tenant' placeholder - the baseline arrives with the 'Exported Template' placeholder; assign real tenants in the editor.")
        }
        $Entry.tenants = @(@($Assignments) | ForEach-Object { "$($_.label ?? $_.value ?? $_)" } | Where-Object { $_ })
        if ($Json.runManually -eq $true) {
            $Warnings.Add("Run-manually carried over: the baseline migrates with 'Disable Scheduled Runs' on - it only executes when you run it.")
        }
        if ($Assignments.Count -eq 0) {
            $Warnings.Add('No tenants are assigned - the baseline imports unassigned and applies nowhere until assigned.')
        }

        $Configs = [System.Collections.Generic.List[object]]::new()
        $StandardReports = [System.Collections.Generic.List[object]]::new()
        foreach ($StandardProperty in $Json.standards.PSObject.Properties) {
            $Entries = if ($StandardProperty.Value -is [array]) { @($StandardProperty.Value) } else { @($StandardProperty.Value) }
            foreach ($V2Entry in $Entries) {
                if (-not $V2Entry) { continue }
                $Mapped = & $MapEntry $StandardProperty.Name $V2Entry $IsDrift
                foreach ($Warning in $Mapped.Warnings) { $Warnings.Add("$($StandardProperty.Name): $Warning") }
                foreach ($Config in @($Mapped.Configs | Where-Object { $_ })) {
                    $Configs.Add($Config)
                    $StandardReports.Add([PSCustomObject]@{
                            standard          = $Config.standard
                            instance          = $Config.instance
                            remediateEnabled  = $Config.remediateEnabled
                            faithfulRemediate = $Config.faithfulRemediate
                            alertEnabled      = $Config.alertEnabled
                        })
                }
            }
        }
        if ($IsDrift -and $AddDetectStandards) {
            foreach ($Detect in @('DetectIntuneDrift', 'DetectConditionalAccessDrift')) {
                if ($DefinitionsByName[$Detect] -and -not ($Configs | Where-Object { $_.standard -eq $Detect })) {
                    $Configs.Add([PSCustomObject]@{
                            standard = $Detect; instance = $Detect
                            variables = [PSCustomObject]@{}
                            remediateEnabled = $false; alertEnabled = $true; alertOnRemediate = $false
                            faithfulRemediate = $false
                        })
                    $StandardReports.Add([PSCustomObject]@{ standard = $Detect; instance = $Detect; remediateEnabled = $false; faithfulRemediate = $false; alertEnabled = $true })
                }
            }
        }
        $Entry.standardsCount = $Configs.Count
        $Entry.standards = @($StandardReports)
        $Entry.warnings = @($Warnings)
        if ($Configs.Count -eq 0) {
            $Entry.status = 'Skipped'
            $Entry.detail = 'No standard in this template could be mapped.'
            continue
        }

        # Idempotency: one baseline per V2 template, keyed by its GUID; the SHA guard
        # skips unchanged re-commits and updates changed ones in place.
        $SourceMarker = "StandardsTemplateV2:$V2Guid"
        $Sha = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes("$($Row.JSON)|reportOnly=$ReportOnly|detect=$AddDetectStandards"))).ToLower()
        $SafeSource = ConvertTo-CIPPODataFilterValue -Value $SourceMarker
        $Existing = Get-CIPPAzDataTableEntity @RolloutTable -Filter "PartitionKey eq 'rollout' and Source eq '$SafeSource'" | Select-Object -First 1
        if ($Existing -and "$($Existing.SHA)" -eq $Sha) {
            $Entry.status = 'UpToDate'
            $Entry.detail = 'Already migrated and unchanged since.'
            continue
        }
        if ($Preview) {
            $Entry.status = $(if ($Existing) { 'WillUpdate' } else { 'Ready' })
            continue
        }

        try {
            $Payload = [PSCustomObject]@{
                GUID            = $(if ($Existing) { $Existing.RowKey } else { $null })
                templateName    = "$($Json.templateName)"
                description     = "$($Json.description)"
                assignedTenants = @($Assignments)
                excludedTenants = @($Json.excludedTenants)
                alertEmails     = $(if ($IsDrift -and -not $Json.driftAlertDisableEmail) { "$($Json.driftAlertEmail)" } else { '' })
                alertWebhookUrl = $(if ($IsDrift) { "$($Json.driftAlertWebhook)" } else { '' })
                # The V2 JSON field keeps its legacy name; only the baseline side renames.
                disableScheduledRuns = [bool]$Json.runManually
                stages          = @([PSCustomObject]@{ name = 'Default'; logic = 'and'; conditions = @(); standards = @($Configs) })
            }
            $Saved = New-CIPPBaseline -Baseline $Payload -User $User -Source $SourceMarker -SHA $Sha
            $Entry.status = $(if ($Existing) { 'Updated' } else { 'Migrated' })
            $Entry.detail = "Baseline $($Saved.GUID): $($Saved.DeltaCount) delta rows."
            Write-LogMessage -API 'Baselines' -message "Migrated V2 template '$($Json.templateName)' ($V2Guid) to baseline $($Saved.GUID) ($($Configs.Count) standards)." -Sev 'Info'
        } catch {
            $Entry.status = 'Failed'
            $Entry.detail = "$($_.Exception.Message)"
            Write-LogMessage -API 'Baselines' -message "Failed to migrate V2 template '$($Json.templateName)' ($V2Guid): $($_.Exception.Message)" -Sev 'Error'
        }
    }

    [PSCustomObject]@{
        templates = @($Report)
        summary   = [PSCustomObject]@{
            total    = @($Report).Count
            ready    = @($Report | Where-Object { $_.status -in @('Ready', 'WillUpdate') }).Count
            migrated = @($Report | Where-Object { $_.status -in @('Migrated', 'Updated') }).Count
            upToDate = @($Report | Where-Object { $_.status -eq 'UpToDate' }).Count
            skipped  = @($Report | Where-Object { $_.status -eq 'Skipped' }).Count
            failed   = @($Report | Where-Object { $_.status -eq 'Failed' }).Count
            warnings = @($Report | ForEach-Object { @($_.warnings).Count } | Measure-Object -Sum).Sum
        }
    }
}
