function Invoke-CIPPBaselineDisableOutlookAddins {
    <#
    .SYNOPSIS
        DisableOutlookAddins executor: removes the user add-in install roles.
    .DESCRIPTION
        The classic's write: for each app-install role still on the default policy, resolve
        its management role assignments and remove them by GUID. Per-role failures log and
        continue; only every role failing is an error, so partial progress is kept. NOTE
        (as in the classic): removal is one-way through CIPP - re-enabling requires
        recreating the assignments in Exchange.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $RolesToRemove = @($Current.rolesToRemove)
    if ($RolesToRemove.Count -eq 0) { return }
    $PolicyIdentity = "$($Current.policyIdentity)"

    $Failures = 0
    foreach ($Role in $RolesToRemove) {
        try {
            $RoleAssignments = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ManagementRoleAssignment' -cmdParams @{ RoleAssignee = $PolicyIdentity; Role = $Role }
            foreach ($Assignment in @($RoleAssignments)) {
                New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-ManagementRoleAssignment' -cmdParams @{ Identity = "$($Assignment.Guid)"; Confirm = $false } -UseSystemMailbox $true
            }
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Removed the Outlook add-in install role '$Role' from the default policy." -Sev 'Info'
        } catch {
            $Failures++
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Failed to remove the Outlook add-in install role '$Role': $($_.Exception.Message)" -Sev 'Error'
        }
    }
    if ($Failures -ge $RolesToRemove.Count) { throw "Every Outlook add-in role removal failed for $TenantFilter - see the log for the first error." }
}
