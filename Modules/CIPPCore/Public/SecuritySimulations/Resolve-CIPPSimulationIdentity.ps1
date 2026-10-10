function Resolve-CIPPSimulationIdentity {
    <#
    .SYNOPSIS
        Picks a real account in the tenant to stand in for a simulation persona.
    .DESCRIPTION
        The What If API evaluates a real identity, so every persona resolves to one from the CIPP cache:
        'admin' is a member of a privileged directory role (Global Administrator first), 'user' an enabled,
        licensed member that holds no privileged role, 'guest' an enabled guest.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$TenantFilter,
        [Parameter(Mandatory = $true)][ValidateSet('admin', 'user', 'guest')]$Persona,
        $Users,
        $Roles,
        $Policies
    )

    if ($null -eq $Users) { $Users = @(Get-CIPPSimulationCache -TenantFilter $TenantFilter -Type 'Users') }
    if ($null -eq $Roles) { $Roles = @(Get-CIPPSimulationCache -TenantFilter $TenantFilter -Type 'Roles') }
    if ($null -eq $Policies) { $Policies = @(Get-CIPPSimulationCache -TenantFilter $TenantFilter -Type 'ConditionalAccessPolicies') }

    $PrivilegedRoleTemplates = @(Get-CIPPPrivilegedRoleTemplateIds)

    $ExcludedUserIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Policy in $Policies) {
        foreach ($Id in @($Policy.conditions.users.excludeUsers | Where-Object { $_ })) { $null = $ExcludedUserIds.Add("$Id") }
    }

    $AdminIds = [System.Collections.Generic.List[string]]::new()
    foreach ($Template in $PrivilegedRoleTemplates) {
        foreach ($Role in @($Roles | Where-Object { $_.roleTemplateId -eq $Template })) {
            foreach ($Member in @($Role.members | Where-Object { $_.id })) {
                if (-not $AdminIds.Contains("$($Member.id)")) { $AdminIds.Add("$($Member.id)") }
            }
        }
    }

    $UsersById = @{}
    foreach ($User in $Users) { if ($User.id) { $UsersById["$($User.id)"] = $User } }

    $Describe = {
        param($User, $Kind)
        [PSCustomObject]@{
            persona           = $Persona
            kind              = $Kind
            userId            = "$($User.id)"
            displayName       = "$($User.displayName)"
            userPrincipalName = "$($User.userPrincipalName)"
        }
    }

    switch ($Persona) {
        'admin' {
            $Candidates = [System.Collections.Generic.List[object]]::new()
            foreach ($Id in $AdminIds) {
                $User = $UsersById[$Id]
                if ($null -eq $User -or $User.accountEnabled -ne $true -or "$($User.userType)" -eq 'Guest') { continue }
                $Candidates.Add($User)
            }
            $Pick = $Candidates | Where-Object { -not $ExcludedUserIds.Contains("$($_.id)") } | Select-Object -First 1
            if (-not $Pick) { $Pick = $Candidates | Select-Object -First 1 }
            if ($Pick) { return (& $Describe $Pick 'Privileged role member') }
        }
        'user' {
            $Pick = $Users | Where-Object {
                $_.accountEnabled -eq $true -and
                "$($_.userType)" -ne 'Guest' -and
                @($_.assignedLicenses | Where-Object { $_ }).Count -gt 0 -and
                -not $AdminIds.Contains("$($_.id)") -and
                -not $ExcludedUserIds.Contains("$($_.id)")
            } | Select-Object -First 1
            if (-not $Pick) {
                $Pick = $Users | Where-Object { $_.accountEnabled -eq $true -and "$($_.userType)" -ne 'Guest' -and -not $AdminIds.Contains("$($_.id)") } | Select-Object -First 1
            }
            if ($Pick) { return (& $Describe $Pick 'Licensed member') }
        }
        'guest' {
            $Pick = $Users | Where-Object { $_.accountEnabled -eq $true -and "$($_.userType)" -eq 'Guest' } | Select-Object -First 1
            if ($Pick) { return (& $Describe $Pick 'Guest') }
        }
    }
    $null
}
