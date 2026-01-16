function Invoke-CippTestZTNA21815 {
    <#
    .SYNOPSIS
    All privileged role assignments are activated just in time and not permanently active
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )
    #tested
    $TestId = 'ZTNA21815'

    try {
        $PrivilegedRoles = Get-CippDbRole -TenantFilter $Tenant -IncludePrivilegedRoles
        $RoleAssignmentScheduleInstances = New-CIPPDbRequest -TenantFilter $Tenant -Type 'RoleAssignmentScheduleInstances'
        $Users = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Users'

        $PermanentAssignments = [System.Collections.Generic.List[object]]::new()

        foreach ($Role in $PrivilegedRoles) {
            $ActiveAssignments = $RoleAssignmentScheduleInstances | Where-Object {
                $_.roleDefinitionId -eq $Role.RoletemplateId -and
                $_.assignmentType -eq 'Assigned' -and
                $null -eq $_.endDateTime
            }

            foreach ($Assignment in $ActiveAssignments) {
                $User = $Users | Where-Object { $_.id -eq $Assignment.principalId } | Select-Object -First 1
                if (-not $User) { continue }

                $PermanentAssignments.Add([PSCustomObject]@{
                        PrincipalDisplayName = $User.displayName
                        UserPrincipalName    = $User.userPrincipalName
                        PrincipalId          = $User.id
                        RoleDisplayName      = $Role.displayName
                        PrivilegeType        = 'Permanent'
                    })
            }
        }

        if ($PermanentAssignments.Count -eq 0) {
            $Passed = $true
            $ResultMarkdown = 'No privileged users have permanent role assignments.'
        } else {
            $Passed = $false
            $ResultMarkdown = "Privileged users with permanent role assignments were found.`n`n"
            $ResultMarkdown += "## Privileged users with permanent role assignments`n`n"
            $ResultMarkdown += "| User | UPN | Role Name | Assignment Type |`n"
            $ResultMarkdown += "| :--- | :-- | :-------- | :-------------- |`n"

            foreach ($Result in $PermanentAssignments) {
                $PortalLink = "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/AdministrativeRole/userId/$($Result.PrincipalId)/hidePreviewBanner~/true"
                $ResultMarkdown += "| [$($Result.PrincipalDisplayName)]($PortalLink) | $($Result.UserPrincipalName) | $($Result.RoleDisplayName) | $($Result.PrivilegeType) |`n"
            }
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'All privileged role assignments are activated just in time and not permanently active' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Privileged access'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'All privileged role assignments are activated just in time and not permanently active' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Privileged access'
    }
}
