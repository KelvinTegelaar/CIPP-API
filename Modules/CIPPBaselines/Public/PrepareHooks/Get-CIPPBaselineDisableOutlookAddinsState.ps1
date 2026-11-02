function Get-CIPPBaselineDisableOutlookAddinsState {
    <#
    .SYNOPSIS
        Prepare hook for DisableOutlookAddins: user add-in install roles on the default
        role assignment policy.
    .DESCRIPTION
        Reads the default role assignment policy live (one small object, no cache) and
        grades whether any of the three app-install roles - My Custom Apps, My Marketplace
        Apps, My ReadWriteMailbox Apps - are still assigned. Any present role means users
        can install add-ins, the classic's exact check.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policy = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RoleAssignmentPolicy' | Where-Object { $_.IsDefault -eq $true } | Select-Object -First 1
    if (-not $Policy) { return @{ Current = $null } }

    $Roles = @('My Custom Apps', 'My Marketplace Apps', 'My ReadWriteMailbox Apps')
    $RolesToRemove = @($Roles | Where-Object { @($Policy.AssignedRoles) -contains $_ })

    $Current = [PSCustomObject]@{
        disabledOutlookAddins = ($RolesToRemove.Count -eq 0)
    }
    # Carried for the executor.
    $Current | Add-Member -NotePropertyName 'policyIdentity' -NotePropertyValue "$($Policy.Identity)"
    $Current | Add-Member -NotePropertyName 'rolesToRemove' -NotePropertyValue @($RolesToRemove)

    @{
        Expected = [PSCustomObject]@{ disabledOutlookAddins = $true }
        Current  = $Current
    }
}
