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
    $DirectRoleAssignments = New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Roles' | Where-Object { $_.roleTemplateId -eq $RoleTemplateId } | Select-Object -ExpandProperty members

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

    foreach ($member in $DirectRoleAssignments) {
        if ($AllMembers.id -notcontains $member.id) {
            $memberObj = [PSCustomObject]@{
                id                = $member.id
                displayName       = $member.displayName
                userPrincipalName = $member.userPrincipalName
                '@odata.type'     = $member.'@odata.type'
                AssignmentType    = 'Direct'
            }
            $AllMembers.Add($memberObj)
        }
    }

    return $AllMembers
}
