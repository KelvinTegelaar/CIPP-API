function Get-CIPPBaselineIntuneTemplateState {
    <#
    .SYNOPSIS
        Prepare hook for IntuneTemplate: normalized Expected/Current per policy family.
    .DESCRIPTION
        Produces the comparable pair for one Intune template against one tenant, reusing
        the V2 pipeline helpers verbatim (nesting repair, text replacement, payload-aware
        policy naming, identity merge, available-settings pruning, fuzzy matching) with
        the current state read from CIPPDb caches. Rules, each closing a documented V2
        false-drift source:
        - the wrapper's Displayname/Description columns merge onto the payload for the
          types deployment does the same to (Device/Compliance/AppProtection/AppConfig) -
          otherwise a template rename drifts forever on the exact fields remediation fixes
        - the policy is looked up under its DEPLOYED name (payload name for Catalog and
          the update-profile families, wrapper column otherwise), after text replacement
        - fuzzy matching (levenshteinDistance) applies to the COMPARE too - V2 only fuzzy
          -matched in remediation, so a renamed policy read as missing forever while
          being happily patched every run
        - reusable-setting references resolve read-only against the tenant's cached
          reusablePolicySettings (V2 WROTE to the tenant during report-only runs)
        - Catalog policies project to name/description/settings/platforms/technologies/
          templateReference on both sides and compare via the shared Catalog flatten;
          Endpoint Security templates prune to the tenant's available settings first
        - compliance policies drop scheduledActionsForRule on BOTH sides (Graph rejects
          it on PATCH, so it is unremediable; the cache does not carry it either)
        - update-profile read-only fields (inventory status, deployable content names,
          end-of-support dates) drop on both sides
        - AppConfiguration drops targetedMobileApps on both sides
        - Admin (ADMX) templates compare EXISTENCE only: the cache carries no
          definitionValues, and V2's deep compare produced order-induced phantom drift
        - Intents templates are not deployable and throw a clear error
        - a missing policy compares against a 'Policy is missing from this tenant'
          marker (drifts -> remediation deploys); an empty family cache returns Current
          $null so the engine's collector-on-miss / No Data / fail-open semantics apply.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Variables = $Item.Variables
    if ($Variables -is [System.Collections.IDictionary]) { $Variables = [PSCustomObject]$Variables }
    $Unwrap = { param($Value) if ($Value -is [System.Management.Automation.PSCustomObject] -and $null -ne $Value.value) { $Value.value } else { $Value } }
    $TemplateRef = "$(& $Unwrap $Variables.intuneTemplate)"
    $MaxDistance = 0
    try { $MaxDistance = [int]"$(& $Unwrap $Variables.levenshteinDistance)" } catch { $MaxDistance = 0 }
    if ($MaxDistance -lt 0) { $MaxDistance = 0 } elseif ($MaxDistance -gt 10) { $MaxDistance = 10 }

    # --- the stored template (prefix RowKey match covers built-ins named <guid>.IntuneTemplate.json)
    $Table = Get-CippTable -tablename 'templates'
    $TemplateRow = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'IntuneTemplate'" | Where-Object { $_.RowKey -like "$TemplateRef*" } | Select-Object -First 1
    if (-not $TemplateRow) { throw "Intune template '$TemplateRef' was not found in the template store." }
    $Template = Repair-CIPPIntuneTemplateNesting -Template ($TemplateRow.JSON | ConvertFrom-Json -Depth 100) -Table $Table

    $TemplateType = Get-CIPPIntuneTemplateType -Type $Template.Type -RawJson $Template.RAWJson
    if (-not $TemplateType) { throw "The type of Intune template '$($Template.Displayname)' could not be determined." }
    if ($TemplateType -eq 'Intents') { throw "Intune template '$($Template.Displayname)' is an Endpoint Security intent, which cannot be deployed or compared." }

    $RawJson = "$($Template.RAWJson)"
    # Read-only reusable-setting resolution: template placeholder GUIDs -> the tenant's
    # cached reusablePolicySettings ids, matched by display name. Unresolved GUIDs stay -
    # that IS drift (the reusable setting is missing) and remediation deploys it.
    foreach ($Reusable in @($Template.ReusableSettings)) {
        if (-not $Reusable) { continue }
        $ReusableGuid = "$($Reusable.GUID ?? $Reusable.guid ?? $Reusable.id)"
        $ReusableName = "$($Reusable.DisplayName ?? $Reusable.displayName ?? $Reusable.name ?? $Reusable.Setting.displayName)"
        if (-not $ReusableGuid -or -not $ReusableName) { continue }
        $TenantReusable = @($(try { New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'IntuneReusableSettings' } catch { $null }) | Where-Object { $_.displayName -eq $ReusableName }) | Select-Object -First 1
        if ($TenantReusable.id) { $RawJson = $RawJson.Replace($ReusableGuid, "$($TenantReusable.id)") }
    }
    $RawJson = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $RawJson -EscapeForJson
    $Payload = $RawJson | ConvertFrom-Json -Depth 100

    $PolicyName = Get-CIPPIntunePolicyName -TemplateType $TemplateType -RawJSON $RawJson -DisplayName $Template.Displayname

    # --- family map: cache type(s), the name property, per-side drops, compare type
    $Family = switch ($TemplateType) {
        'Device' { @{ Caches = @('IntuneDeviceConfigurations'); NameProperty = 'displayName'; Identity = $true } }
        'Catalog' { @{ Caches = @('IntuneConfigurationPolicies'); NameProperty = 'name'; CompareType = 'Catalog'; Project = @('name', 'description', 'settings', 'platforms', 'technologies', 'templateReference') } }
        'deviceCompliancePolicies' { @{ Caches = @('IntuneDeviceCompliancePolicies'); NameProperty = 'displayName'; Identity = $true; Drop = @('scheduledActionsForRule') } }
        'Admin' { @{ Caches = @('IntuneGroupPolicyConfigurations'); NameProperty = 'displayName'; ExistenceOnly = $true } }
        'AppProtection' { @{ Caches = @('IntuneAppProtectionManagedAppPolicies', 'IntuneAppProtectionPolicies'); NameProperty = 'displayName'; Identity = $true; CompareType = 'AppProtection' } }
        'AppConfiguration' { @{ Caches = @('IntuneAppProtectionMobileAppConfigurations', 'IntuneMobileAppConfigurations'); NameProperty = 'displayName'; Identity = $true; Drop = @('targetedMobileApps') } }
        'windowsDriverUpdateProfiles' { @{ Caches = @('IntuneWindowsDriverUpdateProfiles'); NameProperty = 'displayName'; Drop = @('inventorySyncStatus', 'newUpdates', 'deviceReporting', 'approvalType') } }
        'windowsFeatureUpdateProfiles' { @{ Caches = @('IntuneWindowsFeatureUpdateProfiles'); NameProperty = 'displayName'; Drop = @('deployableContentDisplayName', 'endOfSupportDate', 'installLatestWindows10OnWindows11IneligibleDevice') } }
        'windowsQualityUpdatePolicies' { @{ Caches = @('IntuneWindowsQualityUpdatePolicies'); NameProperty = 'displayName' } }
        'windowsQualityUpdateProfiles' { @{ Caches = @('IntuneWindowsQualityUpdateProfiles'); NameProperty = 'displayName'; Drop = @('releaseDateDisplayName', 'deployableContentDisplayName') } }
        default { throw "Intune template type '$TemplateType' is not supported for baseline drift detection." }
    }

    # --- expected side
    if ($Family.Identity) {
        $Payload = Merge-CIPPIntuneTemplateIdentity -Policy $Payload -TemplateType $TemplateType -DisplayName $Template.Displayname -Description "$($Template.Description)"
    }
    if ($TemplateType -eq 'Catalog' -and $Payload.templateReference.templateId) {
        # Endpoint Security: prune to the settings this tenant's licensing makes
        # available, and adopt the tenant's template-reference casing.
        $Payload = $(try { Select-CIPPIntuneAvailableSetting -Policy $Payload -TenantFilter $TenantFilter } catch { $Payload })
    }

    $Normalize = {
        param($Policy)
        $Policy = $Policy | ConvertTo-Json -Depth 100 -Compress | ConvertFrom-Json -Depth 100
        foreach ($DropProperty in @($Family.Drop)) {
            if ($DropProperty) { $Policy.PSObject.Properties.Remove($DropProperty) }
        }
        if ($Family.Project) {
            $Projection = [PSCustomObject]@{}
            foreach ($ProjectProperty in $Family.Project) {
                $Projection | Add-Member -NotePropertyName $ProjectProperty -NotePropertyValue $Policy.$ProjectProperty
            }
            $Policy = $Projection
        }
        # Custom (OMA-URI) policies: templates carry values as strings ('true') while
        # Graph returns typed values (true) - a type difference the shared compare
        # correctly flags but nobody means. Coerce value to string on BOTH sides, drop
        # Graph's decoration (isEncrypted/secretReferenceValueId/empty description) and
        # sort by omaUri so ordering never drifts. The collector decrypts encrypted
        # values at cache time, so value holds the comparable plaintext.
        if ($Policy.PSObject.Properties['omaSettings'] -and $Policy.omaSettings) {
            $Policy.omaSettings = @($(foreach ($OmaSetting in $Policy.omaSettings) {
                        $Clean = [PSCustomObject]@{
                            '@odata.type' = $OmaSetting.'@odata.type'
                            displayName   = "$($OmaSetting.displayName)"
                            omaUri        = "$($OmaSetting.omaUri)"
                            value         = "$($OmaSetting.value)"
                        }
                        if ("$($OmaSetting.description)") { $Clean | Add-Member -NotePropertyName description -NotePropertyValue "$($OmaSetting.description)" }
                        $Clean
                    }) | Sort-Object -Property omaUri)
        }
        $Policy
    }

    $Expected = if ($Family.ExistenceOnly) {
        # Admin/ADMX: the cache has no definitionValues and V2's deep compare produced
        # order-induced phantom drift - presence is the honest check.
        [PSCustomObject]@{ displayName = $PolicyName; deployed = $true }
    } else {
        & $Normalize $Payload
    }

    # --- current side, cache-only
    $Policies = @()
    foreach ($CacheType in $Family.Caches) {
        $Policies = @($(try { New-CIPPDbRequest -TenantFilter $TenantFilter -Type $CacheType } catch { $null }) | Where-Object { $_ })
        if ($Policies.Count -gt 0) { break }
    }
    if ($Policies.Count -eq 0) {
        # Distinguish 'never collected' from 'collected and the tenant genuinely has no
        # policies of this family': the collector stamps a <Type>-Count metadata row even
        # for an empty family. Metadata present means the template's policy is really
        # missing (brand-new tenant) => plain-compare drift so remediation deploys it.
        # No metadata means no data - the engine's collector-on-miss / fail-open takes over.
        foreach ($CacheType in $Family.Caches) {
            $CacheMeta = $(try { Get-CIPPDbItem -TenantFilter $TenantFilter -Type $CacheType -CountsOnly } catch { $null })
            if ($null -ne $CacheMeta) {
                # EmptyFamily: the WHOLE family came back empty, not just this policy.
                # The engine cross-checks against the prior state - a family that held
                # this policy recently going completely empty is more likely a failed
                # or flaky collection than a mass deletion.
                return @{
                    Expected    = $Expected
                    Current     = [PSCustomObject]@{ policyStatus = 'Policy is missing from this tenant' }
                    CompareType = $null
                    EmptyFamily = $true
                }
            }
        }
        return @{ Expected = $Expected; Current = $null; CompareType = $Family.CompareType }
    }

    $MatchSplat = @{
        DisplayName      = $PolicyName
        ExistingPolicies = $Policies
        NameProperty     = $Family.NameProperty
        MaxDistance      = $MaxDistance
    }
    if ($TemplateType -eq 'Catalog' -and $Payload.templateReference.templateId) { $MatchSplat.TemplateId = "$($Payload.templateReference.templateId)" }
    elseif ($Payload.'@odata.type') { $MatchSplat.ODataType = "$($Payload.'@odata.type')" }
    $Match = Find-CIPPFuzzyPolicyMatch @MatchSplat
    $Live = $Match.Policy

    if (-not $Live) {
        # The marker object has no settings, so family compare types (Catalog/AppProtection)
        # would crash flattening it - a plain object compare surfaces the drift correctly.
        return @{
            Expected    = $Expected
            Current     = [PSCustomObject]@{ policyStatus = 'Policy is missing from this tenant' }
            CompareType = $null
        }
    }

    $Current = if ($Family.ExistenceOnly) {
        [PSCustomObject]@{ displayName = "$($Live.displayName)"; deployed = $true }
    } else {
        & $Normalize $Live
    }

    # Assignment verification: target types compare from the CACHED assignments (pure);
    # custom group / filter names resolve via two small Graph reads only when configured.
    # An unknown result ($null, e.g. Graph error) counts as not-assigned, like V2.
    # Note remediation ASSIGNS in append mode - an extra portal-added assignment reports
    # as drift here but is never removed automatically.
    if ((& $Unwrap $Variables.verifyAssignments) -eq $true) {
        $Expected | Add-Member -NotePropertyName 'isAssigned' -NotePropertyValue $true -Force
        $AssignTo = "$(& $Unwrap $Variables.assignTo)"
        $CustomGroup = "$(& $Unwrap $Variables.customGroup)"
        if ($CustomGroup) { $AssignTo = 'customGroup' }
        $AssignmentsMatch = Compare-CIPPIntuneAssignments -ExistingAssignments @($Live.assignments) -ExpectedAssignTo $AssignTo -ExpectedCustomGroup $CustomGroup -ExpectedExcludeGroup "$(& $Unwrap $Variables.excludeGroup)" -ExpectedAssignmentFilter "$(& $Unwrap $Variables.assignmentFilter)" -ExpectedAssignmentFilterType "$(& $Unwrap $Variables.assignmentFilterType)" -TenantFilter $TenantFilter
        $Current | Add-Member -NotePropertyName 'isAssigned' -NotePropertyValue ([bool]$AssignmentsMatch) -Force
    }

    return @{ Expected = $Expected; Current = $Current; CompareType = $Family.CompareType }
}
