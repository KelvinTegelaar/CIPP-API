function Get-CippDbRoleMembers {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$RoleTemplateId
    )

    $RoleAssignments = New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'RoleAssignmentScheduleInstances'
    $RoleEligibilities = New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'RoleEligibilitySchedules'

    $ActiveMembers = $RoleAssignments | Where-Object {
        $_.roleDefinitionId -eq $RoleTemplateId -and $_.assignmentType -eq 'Assigned'
    }

    $EligibleMembers = $RoleEligibilities | Where-Object {
        $_.roleDefinitionId -eq $RoleTemplateId
    }

    $AllMembers = [System.Collections.Generic.List[object]]::new()

    foreach ($member in $ActiveMembers) {
        $memberObj = [PSCustomObject]@{
            id                = $member.principalId
            displayName       = $member.principal.displayName
            userPrincipalName = $member.principal.userPrincipalName
            '@odata.type'     = $member.principal.'@odata.type'
            AssignmentType    = 'Active'
        }
        $AllMembers.Add($memberObj)
    }

    foreach ($member in $EligibleMembers) {
        if ($AllMembers.id -notcontains $member.principalId) {
            $memberObj = [PSCustomObject]@{
                id                = $member.principalId
                displayName       = $member.principal.displayName
                userPrincipalName = $member.principal.userPrincipalName
                '@odata.type'     = $member.principal.'@odata.type'
                AssignmentType    = 'Eligible'
            }
            $AllMembers.Add($memberObj)
        }
    }

    return $AllMembers
}
