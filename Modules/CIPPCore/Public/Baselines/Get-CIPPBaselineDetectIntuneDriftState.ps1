function Get-CIPPBaselineDetectIntuneDriftState {
    <#
    .SYNOPSIS
        Prepare hook for the DetectIntuneDrift standard: flags admin-created policies.
    .DESCRIPTION
        Builds the MANAGED set - the display names of every Intune template any baseline
        applies to this tenant (across ALL baselines, resolved through the same work-item
        resolver the engine runs on) - and compares it against the tenant's live policy
        caches. Every live policy whose name matches no managed template is drift: one
        label-keyed diff per policy, so operators accept or deny-delete each rogue policy
        individually through the per-path triage.
        Matching is by display name, case-insensitive, after tenant-token replacement -
        exactly how the template deploy names its policies. Report-only by design: the
        definition carries no remediate executor, so nothing is ever rewritten - the only
        write is a deletion, and only for a policy an operator explicitly denied.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter)

    # --- managed set: template names from every baseline applying to this tenant
    $ManagedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $TemplatesTable = Get-CippTable -tablename 'templates'
    $WorkItems = @(try { Get-CIPPBaselineWorkItems -TenantFilter $TenantFilter } catch { @() })
    $IntuneWorkItems = @($WorkItems | Where-Object { $_.BaseName -eq 'IntuneTemplate' })
    $AllTemplateRows = if ($IntuneWorkItems.Count -gt 0) {
        @(Get-CIPPAzDataTableEntity @TemplatesTable -Filter "PartitionKey eq 'IntuneTemplate'")
    } else { @() }
    $Unwrap = { param($Value) if ($Value -is [System.Management.Automation.PSCustomObject] -and $null -ne $Value.value) { $Value.value } else { $Value } }
    foreach ($WorkItem in $IntuneWorkItems) {
        $TemplateRef = "$(& $Unwrap $WorkItem.Variables.intuneTemplate)"
        if (-not $TemplateRef) { continue }
        $TemplateRow = $AllTemplateRows | Where-Object { $_.RowKey -like "$TemplateRef*" -or $_.GUID -eq $TemplateRef } | Select-Object -First 1
        if (-not $TemplateRow) { continue }
        $Wrapper = $(try { $TemplateRow.JSON | ConvertFrom-Json -Depth 100 } catch { $null })
        $Payload = $(try { $Wrapper.RAWJson | ConvertFrom-Json -Depth 100 } catch { $null })
        # A template can surface under its payload name (settings catalog) or its wrapper
        # display name (identity families) - count every candidate as managed.
        foreach ($Candidate in @($Payload.name, $Payload.displayName, $Wrapper.Displayname)) {
            if (-not "$Candidate") { continue }
            $Resolved = $(try { Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text "$Candidate" } catch { "$Candidate" })
            $null = $ManagedNames.Add("$Resolved")
        }
    }

    # --- live set: the template-manageable policy families from CIPPDb
    $Families = @(
        @{ Caches = @('IntuneDeviceConfigurations'); Label = 'Device Configuration'; NameProperty = 'displayName'; Resource = 'deviceManagement/deviceConfigurations' }
        @{ Caches = @('IntuneConfigurationPolicies'); Label = 'Settings Catalog'; NameProperty = 'name'; Resource = 'deviceManagement/configurationPolicies' }
        @{ Caches = @('IntuneDeviceCompliancePolicies'); Label = 'Compliance Policy'; NameProperty = 'displayName'; Resource = 'deviceManagement/deviceCompliancePolicies' }
        @{ Caches = @('IntuneGroupPolicyConfigurations'); Label = 'Administrative Template'; NameProperty = 'displayName'; Resource = 'deviceManagement/groupPolicyConfigurations' }
        @{ Caches = @('IntuneAppProtectionManagedAppPolicies', 'IntuneAppProtectionPolicies'); Label = 'App Protection'; NameProperty = 'displayName'; ResourceFromPolicy = $true }
        @{ Caches = @('IntuneAppProtectionMobileAppConfigurations', 'IntuneMobileAppConfigurations'); Label = 'App Configuration'; NameProperty = 'displayName'; Resource = 'deviceAppManagement/mobileAppConfigurations' }
        @{ Caches = @('IntuneWindowsDriverUpdateProfiles'); Label = 'Driver Update'; NameProperty = 'displayName'; Resource = 'deviceManagement/windowsDriverUpdateProfiles' }
        @{ Caches = @('IntuneWindowsFeatureUpdateProfiles'); Label = 'Feature Update'; NameProperty = 'displayName'; Resource = 'deviceManagement/windowsFeatureUpdateProfiles' }
        @{ Caches = @('IntuneWindowsQualityUpdatePolicies'); Label = 'Quality Update'; NameProperty = 'displayName'; Resource = 'deviceManagement/windowsQualityUpdatePolicies' }
        @{ Caches = @('IntuneWindowsQualityUpdateProfiles'); Label = 'Quality Update Profile'; NameProperty = 'displayName'; Resource = 'deviceManagement/windowsQualityUpdateProfiles' }
    )

    $AnyCollected = $false
    $Expected = [PSCustomObject]@{}
    $Current = [PSCustomObject]@{}
    foreach ($Family in $Families) {
        $Policies = @()
        foreach ($CacheType in $Family.Caches) {
            $CacheMeta = $(try { Get-CIPPDbItem -TenantFilter $TenantFilter -Type $CacheType -CountsOnly } catch { $null })
            if ($null -ne $CacheMeta) { $AnyCollected = $true }
            $Policies = @($(try { New-CIPPDbRequest -TenantFilter $TenantFilter -Type $CacheType } catch { $null }) | Where-Object { $_ })
            if ($Policies.Count -gt 0) { break }
        }
        foreach ($Policy in $Policies) {
            $PolicyName = "$($Policy.$($Family.NameProperty))"
            if (-not $PolicyName) { continue }
            if ($ManagedNames.Contains($PolicyName)) { continue }
            $Key = '{0} [{1}]' -f $PolicyName, $Family.Label
            $Resource = if ($Family.ResourceFromPolicy) {
                Get-CIPPIntunePolicyGraphPath -UrlName "$($Policy.URLName ?? $Policy.'@odata.type')"
            } else { $Family.Resource }
            # Unmanaged: expected empty (the policy should be covered by a baseline
            # template or removed), current carries the identifying facts - including the
            # Graph resource the delete executor needs if an operator denies it.
            $Expected | Add-Member -NotePropertyName $Key -NotePropertyValue $null -Force
            $Current | Add-Member -NotePropertyName $Key -NotePropertyValue ([PSCustomObject]@{
                    policyType = $Family.Label
                    id         = "$($Policy.id)"
                    status     = 'Not covered by any baseline template'
                    resource   = "$Resource"
                }) -Force
        }
    }

    if (-not $AnyCollected) {
        # Never collected: the engine's collector-on-miss / No Data semantics take over.
        return @{ Expected = [PSCustomObject]@{}; Current = $null }
    }
    return @{ Expected = $Expected; Current = $Current }
}
