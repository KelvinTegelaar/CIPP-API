function Get-CIPPBaselineBlockUnapprovedRMMState {
    <#
    .SYNOPSIS
        Prepare hook for BlockUnapprovedRMM: whether the Windows and macOS policies that block RMM
        and remote access tools are deployed and match the tool list, the allowed tools and the
        assignment.
    .DESCRIPTION
        Each policy carries a fingerprint in its description. A policy is out of date when the
        fingerprint differs from the one the current settings produce, which also happens when the
        bundled tool list is updated with a CIPP release. A platform that is switched off is not
        graded and its policy is left alone.

        Based on RMM Guard (https://rmmguard.com) by Lewis Barry and Roy Klooster,
        https://github.com/Lewis-Barry/RMM-Blocker
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $V = $Item.Variables
    $Platforms = @(foreach ($Platform in @('Windows', 'macOS')) { if ("$($V.$Platform)" -ne 'False') { $Platform } })
    if ($Platforms.Count -eq 0) {
        return @{ Current = $null; NoDataReason = 'BlockUnapprovedRMM: Windows and macOS are both switched off, so there is nothing to deploy.'; ConfigError = $true }
    }

    $AllowedTools = @($V.allowedTools | ForEach-Object { "$($_.value ?? $_)".Trim() } | Where-Object { $_ })
    $AssignTo = if ("$($V.customGroup)") { "$($V.customGroup)" } else { "$($V.AssignTo.value ?? $V.AssignTo)" }
    $AssignmentKey = "$AssignTo|$($V.excludeGroup)"

    $Expected = [ordered]@{}
    $Wanted = @{}
    try {
        foreach ($Platform in $Platforms) {
            $Policy = Get-CIPPBaselineRmmBlockPolicy -Platform $Platform -AllowedTools $AllowedTools -AssignmentKey $AssignmentKey
            # Every tool with a rule on this platform is allowed, so there is no policy to deploy.
            if (-not $Policy) { continue }
            $Wanted[$Platform] = $Policy
            $Expected["$($Platform.ToLowerInvariant())Policy"] = "Tool list $($Policy.ListVersion), $($Policy.RuleCount) rules [$($Policy.Fingerprint)]"
        }
    } catch {
        return @{ Current = $null; NoDataReason = "$($_.Exception.Message)"; ConfigError = $true }
    }
    if ($Wanted.Count -eq 0) {
        return @{ Current = $null; NoDataReason = 'BlockUnapprovedRMM: every tool is allowed, so there is nothing to block.'; ConfigError = $true }
    }

    $Policies = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'IntuneConfigurationPolicies')
    if ($Policies.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'IntuneConfigurationPolicies')) {
        return @{ Current = $null }
    }

    $Current = [ordered]@{}
    foreach ($Platform in $Wanted.Keys) {
        $Deployed = @($Policies.Where({ "$($_.name)" -eq $Wanted[$Platform].Name })) | Select-Object -First 1
        $Current["$($Platform.ToLowerInvariant())Policy"] = if (-not $Deployed) {
            'Not deployed'
        } elseif ("$($Deployed.description)" -match '\[cfg:([0-9A-F]{16})\]' -and $Matches[1] -eq $Wanted[$Platform].Fingerprint) {
            $Expected["$($Platform.ToLowerInvariant())Policy"]
        } else {
            'Deployed with an older tool list or different settings'
        }
    }

    @{
        Expected = [PSCustomObject]$Expected
        Current  = [PSCustomObject]$Current
    }
}
