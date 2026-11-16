function Get-CIPPBaselineIntuneMinimumOSVersionState {
    <#
    .SYNOPSIS
        Prepare hook for IntuneMinimumOSVersion: compliance and app protection policies whose minimum
        OS version or Android patch level is behind the supported releases on endoflife.date.
    .DESCRIPTION
        A value is behind when it is missing, unreadable or lower than the target; a higher value is
        left alone, so a policy is never lowered. Compliance policies are held to the target after the
        grace period. App protection policies get that as their required version and the target
        without grace as their warning version, so users are warned for the length of the grace period
        before they are blocked.

        Exclusions match the policy display name. An entry without a wildcard matches anywhere in the
        name. They are resolved through Get-CIPPTextReplacement, and a variable left unresolved stops
        the run instead of changing the policy it was meant to protect.

        Based on the approach of IntuneComplianceMaintainer by James Robinson (SkipToTheEndpoint),
        https://github.com/SkipToTheEndpoint/IntuneComplianceMaintainer
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Variables = $Item.Variables
    $CadenceDays = if ([string]::IsNullOrWhiteSpace("$($Variables.cadenceDays)")) { 14 } else { [Math]::Max(0, [int]$Variables.cadenceDays) }
    $Scope = "$($Variables.supportedReleases.value ?? $Variables.supportedReleases)"
    if ($Scope -notin @('supported', 'latestTwo', 'latest')) { $Scope = 'supported' }

    $Patterns = [System.Collections.Generic.List[string]]::new()
    $Entries = @(foreach ($Entry in @($Variables.excludedPolicies)) { $Value = "$($Entry.value ?? $Entry)".Trim(); if ($Value) { $Value } })
    if ($Entries.Count -gt 0) {
        $Resolved = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text (ConvertTo-Json -Compress -InputObject $Entries) -EscapeForJson
        foreach ($Entry in @(ConvertFrom-Json -InputObject $Resolved)) {
            $Value = "$Entry".Trim()
            if ($Value -match '^%[^%\s]+%$') { throw [System.ArgumentException]::new("IntuneMinimumOSVersion: excluded policy $Value is not defined for $TenantFilter. Add it under Custom Variables, globally or for this tenant.") }
            if (-not $Value) { continue }
            $Patterns.Add($(if ($Value -match '[*?]') { $Value } else { "*$([System.Management.Automation.WildcardPattern]::Escape($Value))*" }))
        }
    }

    $Required = @{}
    $Warning = @{}
    try {
        foreach ($Platform in @('Windows', 'macOS', 'iOS', 'Android')) {
            if ($Variables.$Platform -eq $false) { continue }
            $Releases = Get-CIPPOSLifecycle -Product $Platform.ToLowerInvariant()
            $Target = Get-CIPPBaselineMinimumOSTarget -Platform $Platform -Releases $Releases -Scope $Scope -CadenceDays $CadenceDays
            if (-not $Target) { throw "endoflife.date lists no supported $Platform release" }
            $Required[$Platform] = $Target
            $Warning[$Platform] = Get-CIPPBaselineMinimumOSTarget -Platform $Platform -Releases $Releases -Scope $Scope -CadenceDays 0
        }
    } catch {
        return @{ Current = $null; NoDataReason = "$($_.Exception.Message)"; ConfigError = $true }
    }

    $Policies = [System.Collections.Generic.List[object]]::new()
    if ($Variables.compliancePolicies -ne $false) {
        $PlatformByType = @{
            windows10CompliancePolicy          = 'Windows'
            macOSCompliancePolicy              = 'macOS'
            iosCompliancePolicy                = 'iOS'
            androidCompliancePolicy            = 'Android'
            androidWorkProfileCompliancePolicy = 'Android'
            androidDeviceOwnerCompliancePolicy = 'Android'
            aospDeviceOwnerCompliancePolicy    = 'Android'
        }
        foreach ($Policy in @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'IntuneDeviceCompliancePolicies' -CollectorType 'IntunePolicies')) {
            $Type = "$($Policy.'@odata.type')" -replace '^#microsoft\.graph\.'
            $Platform = $PlatformByType[$Type]
            if (-not $Platform -or -not $Required.ContainsKey($Platform)) { continue }
            $Wanted = [ordered]@{ osMinimumVersion = $Required[$Platform].Version }
            if ($Platform -eq 'Android') { $Wanted['minAndroidSecurityPatchLevel'] = $Required[$Platform].PatchLevel }
            $Policies.Add([PSCustomObject]@{ Policy = $Policy; Type = $Type; Kind = "$Platform compliance policy"; Uri = "deviceManagement/deviceCompliancePolicies/$($Policy.id)"; Wanted = $Wanted })
        }
    }
    if ($Variables.appProtectionPolicies -ne $false) {
        $PlatformByType = @{
            windowsManagedAppProtection = 'Windows'
            iosManagedAppProtection     = 'iOS'
            androidManagedAppProtection = 'Android'
        }
        foreach ($Policy in @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'IntuneAppProtectionManagedAppPolicies' -CollectorType 'IntuneAppProtectionPolicies')) {
            $Type = "$($Policy.'@odata.type')" -replace '^#microsoft\.graph\.'
            $Platform = $PlatformByType[$Type]
            if (-not $Platform -or -not $Required.ContainsKey($Platform)) { continue }
            $Wanted = [ordered]@{
                minimumRequiredOsVersion = $Required[$Platform].Version
                minimumWarningOsVersion  = $Warning[$Platform].Version
            }
            if ($Platform -eq 'Android') {
                $Wanted['minimumRequiredPatchVersion'] = $Required[$Platform].PatchLevel
                $Wanted['minimumWarningPatchVersion'] = $Warning[$Platform].PatchLevel
            }
            $Policies.Add([PSCustomObject]@{ Policy = $Policy; Type = $Type; Kind = "$Platform app protection policy"; Uri = "deviceAppManagement/${Type}s/$($Policy.id)"; Wanted = $Wanted })
        }
    }

    $Labels = @{
        osMinimumVersion             = 'minimum OS version'
        minAndroidSecurityPatchLevel = 'minimum security patch level'
        minimumRequiredOsVersion     = 'minimum OS version'
        minimumWarningOsVersion      = 'warning OS version'
        minimumRequiredPatchVersion  = 'minimum security patch level'
        minimumWarningPatchVersion   = 'warning security patch level'
    }
    $Offenders = [System.Collections.Generic.List[string]]::new()
    $Targets = [System.Collections.Generic.List[object]]::new()
    foreach ($Entry in $Policies) {
        $Name = "$($Entry.Policy.displayName)"
        if (@($Patterns.Where({ $Name -like $_ })).Count -gt 0) { continue }

        $Body = [ordered]@{ '@odata.type' = "#microsoft.graph.$($Entry.Type)" }
        $Behind = [System.Collections.Generic.List[string]]::new()
        foreach ($Property in $Entry.Wanted.Keys) {
            $Want = $Entry.Wanted[$Property]
            $Have = "$($Entry.Policy.$Property)".Trim()
            $IsBehind = if ($Property -match 'Patch') {
                # Patch levels are yyyy-MM-dd, which sorts as text.
                $Have -notmatch '^\d{4}-\d{2}-\d{2}$' -or [string]::CompareOrdinal($Have, $Want) -lt 0
            } else {
                $HaveVersion = ConvertTo-CIPPBaselineOSVersion -Text $Have
                -not $HaveVersion -or $HaveVersion -lt (ConvertTo-CIPPBaselineOSVersion -Text $Want)
            }
            if (-not $IsBehind) { continue }
            $Body[$Property] = $Want
            $Behind.Add(('{0} is {1}, should be {2}' -f $Labels[$Property], $(if ($Have) { $Have } else { 'not set' }), $Want))
        }
        if ($Behind.Count -eq 0) { continue }
        $Offenders.Add(('{0} ({1}): {2}' -f $Name, $Entry.Kind, ($Behind -join '; ')))
        $Targets.Add([PSCustomObject]@{ uri = $Entry.Uri; body = [PSCustomObject]$Body })
    }

    @{
        Current = [PSCustomObject]@{
            offenders = @($Offenders | Sort-Object)
            targets   = @($Targets)
        }
    }
}
