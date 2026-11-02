function Get-CIPPBaselineMDMScopeState {
    <#
    .SYNOPSIS
        Prepare hook for MDMScope: the Intune MDM enrollment policy's URLs and user scope.
    .DESCRIPTION
        Grades Microsoft's three fixed Intune URLs plus the appliesTo scope, and - only in
        'selected' scope - whether the configured custom group is among the included
        groups. The cache carries includedGroups expanded to display names for exactly this
        check.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policy = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'MobileDeviceManagementPolicies') | Select-Object -First 1
    if (-not $Policy) { return @{ Current = $null } }

    $AppliesTo = "$($Item.Variables.appliesTo.value ?? $Item.Variables.appliesTo)"
    if ($AppliesTo -notin @('all', 'none', 'selected')) { return @{ Current = $null } }
    $CustomGroup = "$($Item.Variables.customGroup)"
    if ($AppliesTo -eq 'selected' -and [string]::IsNullOrWhiteSpace($CustomGroup)) { return @{ Current = $null } }

    $Expected = [PSCustomObject]@{
        termsOfUseUrl = 'https://portal.manage.microsoft.com/TermsofUse.aspx'
        discoveryUrl  = 'https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc'
        complianceUrl = 'https://portal.manage.microsoft.com/?portalAction=Compliance'
        appliesTo     = $AppliesTo
    }
    $Current = [PSCustomObject]@{
        termsOfUseUrl = "$($Policy.termsOfUseUrl)"
        discoveryUrl  = "$($Policy.discoveryUrl)"
        complianceUrl = "$($Policy.complianceUrl)"
        appliesTo     = "$($Policy.appliesTo)"
    }
    if ($AppliesTo -eq 'selected') {
        $Expected | Add-Member -NotePropertyName 'customGroupIncluded' -NotePropertyValue $true
        $Current | Add-Member -NotePropertyName 'customGroupIncluded' -NotePropertyValue ([bool](@($Policy.includedGroups.displayName) -contains $CustomGroup))
    }

    @{ Expected = $Expected; Current = $Current }
}
