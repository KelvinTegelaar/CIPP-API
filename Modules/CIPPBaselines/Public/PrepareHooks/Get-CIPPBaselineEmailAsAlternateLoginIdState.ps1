function Get-CIPPBaselineEmailAsAlternateLoginIdState {
    <#
    .SYNOPSIS
        Prepare hook for EmailAsAlternateLoginId: the org-default home realm discovery
        policy's AlternateIdLogin flag.
    .DESCRIPTION
        Grades three facts the classic graded: the org-default HRD policy exists, it
        EXPLICITLY carries the AlternateIdLogin setting, and the setting matches - in both
        directions, since disabling email sign-in is as deliberate a posture as enabling it.
        No explicit setting is not the same as disabled: the tenant is then on Microsoft's
        default behaviour, which can change under you, so the classic required the policy to
        say what it means.

        The setting lives in definition[0] as a JSON string inside the policy.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policies = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'HomeRealmDiscoveryPolicy')
    if ($Policies.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'HomeRealmDiscoveryPolicy')) {
        return @{ Current = $null }
    }

    $Desired = [bool]($Item.Variables.Enabled -eq $true)
    $Policy = @($Policies | Where-Object { $_.isOrganizationDefault -eq $true }) | Select-Object -First 1
    $Definition = $(if ($Policy.definition) { try { @($Policy.definition)[0] | ConvertFrom-Json -ErrorAction Stop } catch { $null } })
    $Raw = $Definition.HomeRealmDiscoveryPolicy.AlternateIdLogin.Enabled

    $Current = [PSCustomObject]@{
        policyExists            = [bool]$Policy
        hasExplicitSetting      = ($null -ne $Raw)
        alternateIdLoginEnabled = [bool]($null -ne $Raw -and [bool]$Raw)
    }
    # Carried for the executor: PATCH the existing policy or POST a new org default.
    $Current | Add-Member -NotePropertyName 'policyId' -NotePropertyValue "$($Policy.id)"

    @{
        Expected = [PSCustomObject]@{ policyExists = $true; hasExplicitSetting = $true; alternateIdLoginEnabled = $Desired }
        Current  = $Current
    }
}
