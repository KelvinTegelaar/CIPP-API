function Invoke-CIPPCATemplateBatch {

    # Future Use - Not currently used

    <#
    .SYNOPSIS
        Deploy all Conditional Access template standards for a single tenant in one
        sequential pass, reconciling shared dependencies once up front.
    .DESCRIPTION
        Per-tenant batch path for the ConditionalAccessTemplate standard. Replaces the
        previous one-activity-per-template fan-out (which caused 429 storms against the
        ~1 req/s CA write endpoint, plus duplicate-dependency / c1-c99 / 1040 races) with a
        single serial deployment. Dependencies (named locations, auth contexts, auth
        strengths) are reconciled ONCE via Resolve-CIPPCADependencies, then each policy is
        deployed sequentially using New-CIPPCAPolicy -DependencyMap. Reporting is folded
        into the same loop and remains per-template (one compare field per template).

        Dispatched internally from Push-CIPPStandard when a grouped batch item (carrying
        BatchTemplates) is dequeued. This is NOT a user-selectable standard.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Tenant,
        $Templates,
        [int64]$QueuedTime = 0,
        $Headers
    )

    $Templates = @($Templates | Where-Object { $_ })
    if ($Templates.Count -eq 0) {
        Write-Information "No CA templates to deploy for $Tenant"
        return
    }

    # Always refresh the CA cache first. This is one long-running activity and both Phase 1
    # (dependency reconciliation) and Phase 2 (existing-policy checks / reporting) read off
    # the snapshot, so it must reflect current tenant state before we begin.
    try {
        Write-Information "Refreshing Conditional Access DB cache for $Tenant before batch deploy"
        Set-CIPPDBCacheConditionalAccessPolicies -TenantFilter $Tenant
    } catch {
        Write-Warning "Failed to refresh CA cache for $Tenant : $($_.Exception.Message)"
    }

    # General Entra license gate - applies to every CA template in the batch
    $TestResult = Test-CIPPStandardLicense -StandardName 'ConditionalAccessTemplate_general' -TenantFilter $Tenant -Preset Entra
    if ($TestResult -eq $false) {
        foreach ($t in $Templates) {
            Set-CIPPStandardsCompareField -FieldName "standards.ConditionalAccessTemplate.$($t.Settings.TemplateList.value)" -FieldValue 'This tenant does not have the required license for this standard.' -Tenant $Tenant
        }
        return
    }

    # Preload snapshots from the freshly-updated cache
    try {
        $AllCAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        $PreloadedLocations = New-CIPPDbRequest -TenantFilter $Tenant -Type 'NamedLocations'
        $PreloadedSecurityDefaults = New-CIPPDbRequest -TenantFilter $Tenant -Type 'SecurityDefaults'
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not load the ConditionalAccessTemplate cache for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }
    # Auth strengths are cached; auth contexts are not - Resolve-CIPPCADependencies fetches
    # contexts live and falls back to a live fetch if the strengths snapshot is empty.
    try { $PreloadedAuthStrengths = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationStrengths' } catch { $PreloadedAuthStrengths = $null }

    # Preload tenant-wide lookups ONCE for the whole batch (reused by every policy deploy and the
    # report conversion). Without this, New-CIPPCAPolicy and New-CIPPCATemplate each re-fetch
    # users/groups/servicePrincipals/vacation-groups per policy - dozens of redundant Graph calls.
    $UGRequests = @(
        @{ id = 'users'; url = 'users?$select=id,displayName&$top=999'; method = 'GET' }
        @{ id = 'groups'; url = 'groups?$select=id,displayName&$top=999'; method = 'GET' }
    )
    $PreloadedUsers = $null; $PreloadedGroups = $null; $PreloadedServicePrincipals = $null; $PreloadedVacationGroups = $null
    try {
        $UGResults = New-GraphBulkRequest -Requests $UGRequests -tenantid $Tenant -asapp $true
        $PreloadedUsers = ($UGResults | Where-Object { $_.id -eq 'users' }).body.value
        $PreloadedGroups = ($UGResults | Where-Object { $_.id -eq 'groups' }).body.value
    } catch { Write-Warning "Failed to preload users/groups for $Tenant : $($_.Exception.Message)" }
    try {
        $PreloadedServicePrincipals = New-GraphGETRequest -uri 'https://graph.microsoft.com/v1.0/servicePrincipals?$select=appId&$top=999' -tenantid $Tenant -asApp $true
    } catch { Write-Warning "Failed to preload service principals for $Tenant : $($_.Exception.Message)" }
    try {
        $PreloadedVacationGroups = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/groups?`$filter=startsWith(displayName,'Vacation Exclusion')&`$select=id,displayName&`$top=999&`$count=true" -ComplexFilter -tenantid $Tenant -asApp $true
    } catch { Write-Warning "Failed to preload vacation exclusion groups for $Tenant : $($_.Exception.Message)" }

    $Table = Get-CippTable -tablename 'templates'

    # Load each template's JSON once
    $CATemplates = foreach ($t in $Templates) {
        $TemplateValue = $t.Settings.TemplateList.value
        $Filter = "PartitionKey eq 'CATemplate' and RowKey eq '$TemplateValue'"
        $JSON = (Get-CippAzDataTableEntity @Table -Filter $Filter).JSON
        if (-not $JSON) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Conditional Access template '$($t.Settings.TemplateList.label)' ($TemplateValue) could not be loaded from the template store - skipping." -Sev 'Error'
            Set-CIPPStandardsCompareField -FieldName "standards.ConditionalAccessTemplate.$TemplateValue" -FieldValue "Template '$($t.Settings.TemplateList.label)' could not be loaded from the template store." -Tenant $Tenant
            continue
        }
        [pscustomobject]@{
            Settings      = $t.Settings
            TemplateId    = $t.TemplateId
            RawJSON          = $JSON
            WillRemediate    = $false
            NeedsRemediation = $false
            Skip             = $false
            DeployError      = $null
        }
    }
    $CATemplates = @($CATemplates)
    if ($CATemplates.Count -eq 0) { return }

    # Resolve P2 capability once for the whole tenant (reused for every risk-based policy)
    $TenantHasP2 = [bool](Test-CIPPStandardLicense -StandardName 'ConditionalAccessTemplate_p2' -TenantFilter $Tenant -Preset EntraP2 -SkipLog)

    # Nested helper: compare ONE template against the current deployed state, write its compare
    # field in the renderable CurrentValue/ExpectedValue shape, and return a status string:
    # 'Compliant' | 'Drifted' | 'Missing' | 'P2Blocked' | 'Failed' | 'Error'.
    function Set-CABatchCompareStatus {
        param($ct)
        $Settings = $ct.Settings
        $TemplateValue = $Settings.TemplateList.value
        $FieldName = "standards.ConditionalAccessTemplate.$TemplateValue"

        Set-CippStandardInfoContext -StandardInfo @{
            Standard                    = 'ConditionalAccessTemplate'
            StandardTemplateId          = $ct.TemplateId
            ConditionalAccessTemplateId = $TemplateValue
        }

        try {
            $Policy = $ct.RawJSON | ConvertFrom-Json -Depth 10
            if ($null -eq $Policy) {
                Set-CIPPStandardsCompareField -FieldName $FieldName -CurrentValue @{ Differences = "Template '$($Settings.TemplateList.label)' could not be parsed." } -ExpectedValue @{ Differences = @() } -Tenant $Tenant
                return 'Error'
            }

            # Override the template's state with the standard's state for drift comparison
            if ($Settings.state -and $Settings.state -ne 'donotchange') {
                $Policy | Add-Member -NotePropertyName 'state' -NotePropertyValue $Settings.state -Force
            }

            # Resolve the template's location GUIDs to display names so they compare like-for-like
            # with the deployed policy. The template's OWN LocationInfo carries the id->name map
            # (the GUID is the source tenant's id); fall back to this tenant's named-location cache.
            if ($Policy.conditions.locations) {
                $LocNameById = @{}
                foreach ($li in @($Policy.LocationInfo)) { if ($li.id -and $li.displayName) { $LocNameById[$li.id] = $li.displayName } }
                foreach ($pl in @($PreloadedLocations)) { if ($pl.id -and $pl.displayName -and -not $LocNameById.ContainsKey($pl.id)) { $LocNameById[$pl.id] = $pl.displayName } }
                foreach ($LocDir in 'includeLocations', 'excludeLocations') {
                    if ($Policy.conditions.locations.PSObject.Properties.Name -contains $LocDir -and $Policy.conditions.locations.$LocDir) {
                        $Policy.conditions.locations.$LocDir = @($Policy.conditions.locations.$LocDir | ForEach-Object {
                                if ($LocNameById.ContainsKey($_)) { $LocNameById[$_] } else { $_ }
                            })
                    }
                }
            }

            $CheckExisting = $AllCAPolicies | Where-Object -Property displayName -EQ $Settings.TemplateList.label
            if ($CheckExisting -is [array] -and $CheckExisting.Count -gt 1) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Found $($CheckExisting.Count) Conditional Access policies named '$($Settings.TemplateList.label)' in $Tenant. Comparing against the first; duplicate policies should be cleaned up." -Sev 'Warning'
                $CheckExisting = $CheckExisting[0]
            }

            if (!$CheckExisting) {
                $NeedsP2 = ($Policy.conditions.userRiskLevels.Count -gt 0 -or $Policy.conditions.signInRiskLevels.Count -gt 0)
                if ($ct.DeployError) {
                    Set-CIPPStandardsCompareField -FieldName $FieldName -CurrentValue @{ Differences = "Failed to deploy: $($ct.DeployError)" } -ExpectedValue @{ Differences = @() } -Tenant $Tenant
                    return 'Failed'
                } elseif ($NeedsP2 -and -not $TenantHasP2) {
                    Set-CIPPStandardsCompareField -FieldName $FieldName -CurrentValue @{ Differences = 'Policy requires an AAD Premium P2 license, which this tenant does not have.' } -ExpectedValue @{ Differences = @() } -Tenant $Tenant
                    return 'P2Blocked'
                } else {
                    Set-CIPPStandardsCompareField -FieldName $FieldName -CurrentValue @{ Differences = 'Policy is missing from this tenant.' } -ExpectedValue @{ Differences = @() } -Tenant $Tenant
                    return 'Missing'
                }
            }

            $templateResult = New-CIPPCATemplate -TenantFilter $Tenant -JSON $CheckExisting -preloadedLocations $PreloadedLocations -preloadedUsers $PreloadedUsers -preloadedGroups $PreloadedGroups
            $CompareObj = ConvertFrom-Json -ErrorAction SilentlyContinue -InputObject $templateResult
            if ($null -eq $CompareObj) {
                Set-CIPPStandardsCompareField -FieldName $FieldName -CurrentValue @{ Differences = 'Tenant policy conversion returned null.' } -ExpectedValue @{ Differences = @() } -Tenant $Tenant
                return 'Error'
            }
            try {
                $Compare = Compare-CIPPIntuneObject -ReferenceObject $Policy -DifferenceObject $CompareObj -CompareType 'ca'
            } catch {
                Set-CIPPStandardsCompareField -FieldName $FieldName -CurrentValue @{ Differences = "Error comparing policy: $($_.Exception.Message)" } -ExpectedValue @{ Differences = @() } -Tenant $Tenant
                return 'Error'
            }
            if (!$Compare) {
                Set-CIPPStandardsCompareField -FieldName $FieldName -FieldValue $true -CurrentValue @{ Differences = 'No Differences found' } -ExpectedValue @{ Differences = 'No Differences found' } -Tenant $Tenant
                return 'Compliant'
            } else {
                Set-CIPPStandardsCompareField -FieldName $FieldName -CurrentValue @{ Differences = $Compare } -ExpectedValue @{ Differences = @() } -Tenant $Tenant
                return 'Drifted'
            }
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Error evaluating conditional access template $TemplateValue. Error: $ErrorMessage" -sev 'Error'
            return 'Error'
        }
    }

    # Per-template rerun decision (marker written here so a redelivered batch skips handled ones)
    foreach ($ct in $CATemplates) {
        if ($QueuedTime -gt 0) {
            $API = "ConditionalAccessTemplate_$($ct.TemplateId)_$($ct.Settings.TemplateList.value)"
            if (Test-CIPPRerun -Type Standard -Tenant $Tenant -API $API -Settings $ct.Settings -BaseTime $QueuedTime) {
                Write-Information "Detected rerun for $API. Skipping."
                $ct.Skip = $true
            }
        }
    }

    # ---- Evaluate: compare every in-scope template against the CURRENT state, write its result,
    # and flag only the ones that actually need remediation (missing or drifted). Compliant
    # policies are reported and then left untouched - no needless PATCH on every run. ----
    foreach ($ct in $CATemplates) {
        if ($ct.Skip) { continue }
        if (-not ($ct.Settings.report -eq $true -or $ct.Settings.remediate -eq $true)) { continue }
        $Status = Set-CABatchCompareStatus -ct $ct
        if ($ct.Settings.remediate -eq $true -and $Status -in @('Missing', 'Drifted')) {
            $ct.WillRemediate = $true
            $ct.NeedsRemediation = $true
        }
    }

    # ---- Reconcile shared dependencies ONCE, only for the policies we will actually deploy ----
    $DeployObjects = [System.Collections.Generic.List[object]]::new()
    foreach ($ct in $CATemplates) {
        if ($ct.NeedsRemediation) { $DeployObjects.Add(($ct.RawJSON | ConvertFrom-Json)) }
    }
    $DependencyMap = $null
    if ($DeployObjects.Count -gt 0) {
        try {
            $DependencyMap = Resolve-CIPPCADependencies -TenantFilter $Tenant -PolicyObjects $DeployObjects -AllNamedLocations $PreloadedLocations -AllAuthStrengthPolicies $PreloadedAuthStrengths -Overwrite $true -Headers $Headers -APIName 'Standards'
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to reconcile Conditional Access dependencies for $Tenant. Error: $ErrorMessage" -sev 'Error'
            $DependencyMap = $null
        }
    }

    # ---- Remediate: deploy only the missing/drifted policies, sequentially ----
    $RemediatedAny = $false
    foreach ($ct in $CATemplates) {
        if (-not $ct.NeedsRemediation -or -not $DependencyMap) { continue }
        $Settings = $ct.Settings
        $TemplateValue = $Settings.TemplateList.value
        Set-CippStandardInfoContext -StandardInfo @{
            Standard                    = 'ConditionalAccessTemplate'
            StandardTemplateId          = $ct.TemplateId
            ConditionalAccessTemplateId = $TemplateValue
        }
        try {
            $NewCAPolicy = @{
                replacePattern             = 'displayName'
                TenantFilter               = $Tenant
                state                      = $Settings.state
                RawJSON                    = $ct.RawJSON
                Overwrite                  = $true
                APIName                    = 'Standards'
                Headers                    = $Headers
                DisableSD                  = $Settings.DisableSD
                CreateGroups               = $Settings.CreateGroups ?? $false
                PreloadedCAPolicies        = $AllCAPolicies
                PreloadedLocations         = $PreloadedLocations
                PreloadedSecurityDefaults  = $PreloadedSecurityDefaults
                DependencyMap              = $DependencyMap
                PreloadedServicePrincipals = $PreloadedServicePrincipals
                PreloadedUsers             = $PreloadedUsers
                PreloadedGroups            = $PreloadedGroups
                PreloadedVacationGroups    = $PreloadedVacationGroups
            }
            $null = New-CIPPCAPolicy @NewCAPolicy
            $RemediatedAny = $true
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            # Record the deploy failure so the re-report surfaces the reason instead of "missing"
            $ct.DeployError = $ErrorMessage
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create or update conditional access rule from template $TemplateValue. Error: $ErrorMessage" -sev 'Error'
        }
    }

    # ---- Refresh + re-report ONLY the policies we just deployed ----
    # Only refresh when something actually changed ($RemediatedAny is set on a successful
    # create/update). When nothing was deployed there's no need to re-pull the cache at all.
    if ($RemediatedAny) {
        # Give Graph a moment to propagate the new/updated policies before refreshing the cache,
        # otherwise the refresh can race ahead of eventual consistency and miss just-created ones.
        Start-Sleep -Seconds 5
        try {
            Set-CIPPDBCacheConditionalAccessPolicies -TenantFilter $Tenant
            $AllCAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
            $PreloadedLocations = New-CIPPDbRequest -TenantFilter $Tenant -Type 'NamedLocations'
            # Refresh groups too so the report resolves any exclusion groups just created during deploy
            $UGResults = New-GraphBulkRequest -Requests $UGRequests -tenantid $Tenant -asapp $true
            $PreloadedUsers = ($UGResults | Where-Object { $_.id -eq 'users' }).body.value
            $PreloadedGroups = ($UGResults | Where-Object { $_.id -eq 'groups' }).body.value
        } catch {
            Write-Warning "Failed to refresh CA snapshot after remediation for $Tenant : $($_.Exception.Message)"
        }
        foreach ($ct in $CATemplates) {
            if ($ct.NeedsRemediation -and -not $ct.Skip) {
                $null = Set-CABatchCompareStatus -ct $ct
            }
        }
    }

    Set-CippStandardInfoContext -StandardInfo $null
}
