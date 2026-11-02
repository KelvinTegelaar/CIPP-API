function Get-CippDbRoleMembers {
    <#
    .SYNOPSIS
        Resolve the members of a directory role from cached PIM + directoryRole data.

    .DESCRIPTION
        Merges three sources into one member list, de-duplicated by principal id:
          Active   - PIM roleAssignmentScheduleInstances with assignmentType 'Assigned'
          Eligible - PIM roleEligibilitySchedules (can activate, not currently active)
          Direct   - directoryRole membership assigned outside PIM

        A principal may be a user, a servicePrincipal, or a group — use '@odata.type' to tell
        them apart. userPrincipalName is null for anything that isn't a user, and appId is
        populated only for servicePrincipals.

    .PARAMETER TenantFilter
        The tenant to resolve members for.

    .PARAMETER RoleTemplateId
        The role's TEMPLATE id (e.g. Global Administrator = 62e90394-69f5-4237-9190-012177145e10).

        NOT the directoryRole instance id. PIM's roleDefinitionId carries template ids, so passing
        an instance id (Roles.id) matches nothing and silently returns an empty list. When starting
        from a Get-CippDbRole record, pass $Role.roleTemplateId — never $Role.id.

    .OUTPUTS
        PSCustomObject per member:
          id                - principal object id
          displayName       - principal display name
          userPrincipalName - users only; null for servicePrincipals and groups
          appId             - servicePrincipals only; null otherwise
          '@odata.type'     - '#microsoft.graph.user' | '...servicePrincipal' | '...group'
          AssignmentType    - 'Active' | 'Eligible' | 'Direct'
          EndDateTime       - when the assignment expires; null when it does not
          IsPermanent       - $true when the assignment has no expiry

    .NOTES
        Depends on the cached records carrying an expanded 'principal' object — the Graph APIs
        return only principalId by default, so the collectors request $expand=principal. Without
        it every displayName/userPrincipalName here is null.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$RoleTemplateId
    )

    $RoleAssignments = Get-CIPPTestData -TenantFilter $TenantFilter -Type 'RoleAssignmentScheduleInstances'
    $RoleEligibilities = Get-CIPPTestData -TenantFilter $TenantFilter -Type 'RoleEligibilitySchedules'
    $DirectRoleAssignments = Get-CIPPTestData -TenantFilter $TenantFilter -Type 'Roles' | Where-Object { $_.roleTemplateId -eq $RoleTemplateId } | Select-Object -ExpandProperty members

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
            appId             = $member.principal.appId
            '@odata.type'     = $member.principal.'@odata.type'
            AssignmentType    = 'Active'
            EndDateTime       = $member.endDateTime
            # A PIM assignment with no endDateTime never expires.
            IsPermanent       = ($null -eq $member.endDateTime)
        }
        $AllMembers.Add($memberObj)
    }

    foreach ($member in $EligibleMembers) {
        if ($AllMembers.id -notcontains $member.principalId) {
            $memberObj = [PSCustomObject]@{
                id                = $member.principalId
                displayName       = $member.principal.displayName
                userPrincipalName = $member.principal.userPrincipalName
                appId             = $member.principal.appId
                '@odata.type'     = $member.principal.'@odata.type'
                AssignmentType    = 'Eligible'
                # Eligibilities carry their expiry under scheduleInfo, not endDateTime.
                EndDateTime       = $member.scheduleInfo.expiration.endDateTime
                IsPermanent       = ($member.scheduleInfo.expiration.type -eq 'noExpiration')
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
                appId             = $member.appId
                '@odata.type'     = $member.'@odata.type'
                AssignmentType    = 'Direct'
                # directoryRole membership assigned outside PIM has no expiry.
                EndDateTime       = $null
                IsPermanent       = $true
            }
            $AllMembers.Add($memberObj)
        }
    }

    return $AllMembers
}
