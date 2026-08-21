function Get-CIPPBaselineOauthConsentState {
    <#
    .SYNOPSIS
        Prepare hook for OauthConsent: is user consent routed through the CIPP consent
        policy with the allowed apps included.
    .DESCRIPTION
        Two graded facts, the classic's: the default user role's permission grant policy is
        ManagePermissionGrantsForSelf.cipp-consent-policy, and every expected include exists
        on that policy - the fixed Office 365 Management delegated include plus, per allowed
        app, a delegated and an application include. Extra includes an operator added are
        not graded; the remediation only ever adds, so grading extras would be permanent
        unfixable drift.

        The includes read is LIVE: the policy's include children are not cached, and the
        classic read them live for the same reason. A read failure on a tenant that has
        never had the policy created reads as no includes, which is the honest state.

        The classic's OauthConsentLowSec conflict check is not ported: it inspected the
        CLASSIC standards configuration, which does not exist for baselines - an equivalent
        would compare against other baseline standards, which the engine's conflict
        detection already covers.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $AuthPolicy = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'AuthorizationPolicy') | Select-Object -First 1
    if (-not $AuthPolicy) { return @{ Current = $null } }

    $AllowedApps = @("$($Item.Variables.AllowedApps)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique)

    $Includes = @(try {
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies/cipp-consent-policy/includes' -tenantid $TenantFilter -ErrorAction Stop
        } catch { @() })

    $ExpectedIncludes = [System.Collections.Generic.List[string]]::new()
    $ExpectedIncludes.Add('delegated|00b41c95-dab0-4487-9791-b9d2c32c80f2')
    foreach ($App in $AllowedApps) {
        $ExpectedIncludes.Add("delegated|$App")
        $ExpectedIncludes.Add("application|$App")
    }
    $Missing = @(foreach ($Key in $ExpectedIncludes) {
            $Type, $AppId = $Key -split '\|'
            $Found = $Includes | Where-Object { "$($_.permissionType)".ToLowerInvariant() -eq $Type -and @($_.clientApplicationIds) -contains $AppId }
            if (-not $Found) { $Key }
        })

    $Current = [PSCustomObject]@{
        consentPolicyAssigned = [bool](@($AuthPolicy.permissionGrantPolicyIdsAssignedToDefaultUserRole) -contains 'ManagePermissionGrantsForSelf.cipp-consent-policy')
        missingIncludes       = @($Missing | Sort-Object)
    }
    # Carried for the executor.
    $Current | Add-Member -NotePropertyName 'policyExists' -NotePropertyValue ([bool]($Includes.Count -gt 0))

    @{
        Expected = [PSCustomObject]@{ consentPolicyAssigned = $true; missingIncludes = @() }
        Current  = $Current
    }
}
