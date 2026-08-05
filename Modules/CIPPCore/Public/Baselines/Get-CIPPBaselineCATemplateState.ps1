function Get-CIPPBaselineCATemplateState {
    <#
    .SYNOPSIS
        Prepare hook for ConditionalAccessTemplate: normalized Expected/Current for compare.
    .DESCRIPTION
        Produces the comparable pair for one CA template against one tenant, entirely from
        CIPPDb caches - no live Graph at compare time, and NO frontend compare help: the
        engine's verdict is the only verdict. Both sides normalize to one canonical
        vocabulary; every rule below closes a documented false-drift source from the old
        standards engine:
        - id/GUID/*time*/templateId/@odata/LocationInfo/AuthContextInfo stripped everywhere
          (GUID and AuthContextInfo were NOT excluded by the shared compare and drifted
          forever; AuthContextInfo carries source-tenant descriptions)
        - null-valued properties stripped on BOTH sides, sessionControls scrubbed on BOTH
          sides (the old engine scrubbed the template only, so a live policy full of null
          session controls drifted against a scrubbed template)
        - both sides parse at the same JSON depth (the old 10-vs-1024 mismatch truncated
          one side to strings and reported type-mismatch drift)
        - locations translate GUID->displayName via the template's LocationInfo plus the
          tenant NamedLocations cache; All/AllTrusted pass through
        - users/groups translate GUID->displayName via the Users/Groups caches; unresolved
          GUIDs stay GUIDs so raw-GUID templates still match
        - the tenant's 'Vacation Exclusion*' groups are removed from the live excludeGroups
          (New-CIPPCAPolicy re-adds them on every deploy - deliberate, not drift)
        - grantControls.authenticationStrength collapses to @{ displayName } on both sides
          (deploy matches strengths by displayName; ids and allowedCombinations order are
          tenant-specific noise)
        - state: expected = the configured state (lowercase); 'donotchange' adopts the live
          state so state never drifts
        - the live policy is matched by the TEMPLATE's displayName (never a stale selector
          label); duplicates warn and take the first
        - policy present in cache data but absent from the tenant -> Current becomes a
          'Policy is missing from this tenant' marker so the row drifts and remediation
          deploys; an empty policies cache returns Current $null so the engine's
          collector-on-miss / No Data / fail-open semantics apply unchanged.
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
    $TemplateRef = "$(& $Unwrap $Variables.caTemplate)"
    $ConfiguredState = "$(& $Unwrap $Variables.state)".ToLower()

    # --- the stored template: by GUID (RowKey, then GUID column), displayName as legacy fallback
    $Table = Get-CippTable -tablename 'templates'
    $SafeRef = ConvertTo-CIPPODataFilterValue -Value $TemplateRef
    $TemplateRow = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CATemplate' and RowKey eq '$SafeRef'" | Select-Object -First 1
    if (-not $TemplateRow) {
        $TemplateRow = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CATemplate'" | Where-Object {
            $_.GUID -eq $TemplateRef -or $(try { ($_.JSON | ConvertFrom-Json).displayName } catch { $null }) -eq $TemplateRef
        } | Select-Object -First 1
    }
    if (-not $TemplateRow) { throw "Conditional Access template '$TemplateRef' was not found in the template store." }
    $Template = $TemplateRow.JSON | ConvertFrom-Json -Depth 100

    # --- lookup maps, cache-only
    $NameById = @{}
    foreach ($Location in @($Template.LocationInfo)) {
        if ($Location.id -and $Location.displayName) { $NameById["$($Location.id)"] = "$($Location.displayName)" }
    }
    foreach ($Location in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'NamedLocations' | Where-Object { $_ })) {
        if ($Location.id -and $Location.displayName -and -not $NameById.ContainsKey("$($Location.id)")) { $NameById["$($Location.id)"] = "$($Location.displayName)" }
    }
    $StrengthNameById = @{}
    foreach ($Strength in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'AuthenticationStrengths' | Where-Object { $_ })) {
        if ($Strength.id -and $Strength.displayName) { $StrengthNameById["$($Strength.id)"] = "$($Strength.displayName)" }
    }
    foreach ($Directory in @('Users', 'Groups')) {
        foreach ($Entry in @($(try { New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Directory } catch { $null }) | Where-Object { $_ })) {
            if ($Entry.id -and $Entry.displayName -and -not $NameById.ContainsKey("$($Entry.id)")) { $NameById["$($Entry.id)"] = "$($Entry.displayName)" }
        }
    }

    $TranslateSet = {
        param($Values)
        # The comma keeps single-element results as arrays across the scriptblock
        # boundary - a bare array output enumerates and ['x'] collapses to 'x'.
        , @(foreach ($Value in @($Values)) { $NameById["$Value"] ?? $Value })
    }

    # One normalizer for BOTH sides - symmetry is the whole point.
    $Scrub = $null
    $Scrub = {
        param($Node)
        if ($Node -isnot [System.Management.Automation.PSCustomObject]) { return }
        foreach ($Property in @($Node.PSObject.Properties)) {
            if ($Property.Name -in @('id', 'GUID', 'templateId', 'LocationInfo', 'AuthContextInfo') -or
                $Property.Name -like '*time*' -or $Property.Name -like '*@odata*' -or $null -eq $Property.Value) {
                $Node.PSObject.Properties.Remove($Property.Name)
                continue
            }
            if ($Property.Value -is [System.Management.Automation.PSCustomObject]) {
                & $Scrub $Property.Value
                if (@($Property.Value.PSObject.Properties).Count -eq 0) { $Node.PSObject.Properties.Remove($Property.Name) }
            } elseif ($Property.Value -is [array]) {
                foreach ($Element in $Property.Value) { & $Scrub $Element }
            }
        }
    }

    $Normalize = {
        param($Policy, [bool]$IsLive)
        # Same-depth JSON round trip: a private deep clone both sides share.
        $Policy = $Policy | ConvertTo-Json -Depth 100 -Compress | ConvertFrom-Json -Depth 100

        # authenticationStrength -> displayName only, resolved via the tenant cache for
        # live policies that carry just an id.
        if ($Policy.grantControls.authenticationStrength) {
            $Strength = $Policy.grantControls.authenticationStrength
            $StrengthName = $Strength.displayName ?? $StrengthNameById["$($Strength.id)"]
            $Policy.grantControls.authenticationStrength = [PSCustomObject]@{ displayName = $StrengthName ?? "$($Strength.id)" }
        }

        if ($Policy.conditions.locations) {
            foreach ($Side in @('includeLocations', 'excludeLocations')) {
                if ($null -ne $Policy.conditions.locations.$Side) {
                    $Policy.conditions.locations.$Side = & $TranslateSet $Policy.conditions.locations.$Side
                }
            }
        }
        if ($Policy.conditions.users) {
            foreach ($Side in @('includeUsers', 'excludeUsers', 'includeGroups', 'excludeGroups')) {
                if ($null -ne $Policy.conditions.users.$Side) {
                    $Policy.conditions.users.$Side = & $TranslateSet $Policy.conditions.users.$Side
                }
            }
            if ($IsLive -and $null -ne $Policy.conditions.users.excludeGroups) {
                # CIPP re-adds Vacation Exclusion groups on every deploy - tolerated, not drift.
                $Policy.conditions.users.excludeGroups = @($Policy.conditions.users.excludeGroups | Where-Object { -not "$_".StartsWith('Vacation Exclusion') })
            }
        }

        & $Scrub $Policy
        # sessionControls scrub AFTER the null strip, applied to BOTH sides: drop
        # disableResilienceDefaults unless explicitly true, drop the object when empty.
        if ($Policy.sessionControls) {
            if ($Policy.sessionControls.disableResilienceDefaults -ne $true) { $Policy.sessionControls.PSObject.Properties.Remove('disableResilienceDefaults') }
            if (@($Policy.sessionControls.PSObject.Properties).Count -eq 0) { $Policy.PSObject.Properties.Remove('sessionControls') }
        }
        $Policy
    }

    $Expected = & $Normalize $Template $false

    # --- the live side, from the ConditionalAccessPolicies cache
    $Policies = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ConditionalAccessPolicies' | Where-Object { $_ })
    if ($Policies.Count -eq 0) {
        # No cache data at all: the engine's collector-on-miss / No Data / fail-open
        # semantics take over.
        return @{ Expected = $Expected; Current = $null }
    }

    $Live = @($Policies | Where-Object { $_.displayName -eq $Template.displayName })
    if ($Live.Count -gt 1) {
        Write-Information "Baselines: $($Live.Count) CA policies named '$($Template.displayName)' exist on $TenantFilter - comparing the first."
    }
    $Live = $Live | Select-Object -First 1
    if (-not $Live) {
        if ($ConfiguredState -and $ConfiguredState -ne 'donotchange') { $Expected.state = $ConfiguredState }
        return @{
            Expected = $Expected
            Current  = [PSCustomObject]@{ policyStatus = 'Policy is missing from this tenant' }
        }
    }

    $Current = & $Normalize $Live $true
    # State: the configured state is the expectation; 'donotchange' adopts the live state.
    $Expected.state = if (-not $ConfiguredState -or $ConfiguredState -eq 'donotchange') { $Current.state } else { $ConfiguredState }

    return @{ Expected = $Expected; Current = $Current }
}
