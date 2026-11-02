function Get-CIPPBaselineOutOfScopeAssignment {
    <#
    .SYNOPSIS
        Lists the baseline assignments the calling user's role does not cover.
    .DESCRIPTION
        Empty when the caller may edit or run the baseline: their role is unrestricted, or every
        assignment is a tenant or tenant group the role allows. AllTenants needs unrestricted
        tenant access. Reads the request scope, so it must live in CIPPCore.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Assignments)

    $AllowedTenants = $null
    if ($script:CippAllowedTenantsStorage) { $AllowedTenants = $script:CippAllowedTenantsStorage.Value }
    $AllowedGroups = $null
    if ($script:CippAllowedGroupsStorage) { $AllowedGroups = $script:CippAllowedGroupsStorage.Value }
    if ($null -eq $AllowedTenants -and $null -eq $AllowedGroups) { return }

    $Groups = @(try { Get-TenantGroups } catch { Write-Information "Get-CIPPBaselineOutOfScopeAssignment: tenant group lookup failed: $($_.Exception.Message)" })
    $TenantLookup = Get-CIPPTenantLookup
    foreach ($Assignment in @($Assignments)) {
        if ($null -eq $Assignment) { continue }
        $Value = if ($Assignment -is [string]) { $Assignment } else { "$($Assignment.value)" }
        # 'Exported Template' is the community-export placeholder, never a runnable tenant.
        if (-not $Value -or $Value -eq 'Exported Template') { continue }
        $Group = $Groups.Where({ $_.Id -eq $Value -or $_.Name -eq $Value }, 'First')[0]
        $InScope = if ($Value -eq 'AllTenants') {
            $null -eq $AllowedTenants
        } elseif ($Group) {
            $null -eq $AllowedGroups -or $AllowedGroups -contains $Group.Id
        } else {
            $null -eq $AllowedTenants -or ($TenantLookup[$Value].customerId -and $AllowedTenants -contains $TenantLookup[$Value].customerId)
        }
        if (-not $InScope) {
            if ($Assignment -is [string]) { $Value } else { "$($Assignment.label ?? $Value)" }
        }
    }
}
