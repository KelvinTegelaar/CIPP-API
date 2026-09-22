function Get-CIPPPrivilegedRoleTemplateIds {
    <#
    .SYNOPSIS
        Returns the Entra role TEMPLATE ids that CIPP treats as privileged.

    .DESCRIPTION
        Single source for every "privileged roles" scope in CIPP: Get-CippDbRole, the PIM role
        assignment surfaces, the PIM role settings templates and the PermanentActiveAdminAssigned
        alert all use this list so that the phrase means the same roles everywhere.

        Template ids are what PIM's roleDefinitionId carries for built-in roles, so these compare
        directly against roleAssignmentScheduleInstances / roleEligibilitySchedules records.

    .PARAMETER Set
        Privileged          - CIPP's privileged set (18 roles). Default.
        CisaHighlyPrivileged - the six roles CISA SCuBA calls highly privileged.
        GlobalAdministrator - only Global Administrator.

    .PARAMETER WithNames
        Return objects with Id and DisplayName instead of bare ids, for callers that need a
        name fallback when the tenant's role definitions are not at hand (cached AllTenants views).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Privileged', 'CisaHighlyPrivileged', 'GlobalAdministrator')]
        [string]$Set = 'Privileged',

        [switch]$WithNames
    )

    $Catalog = [ordered]@{
        '62e90394-69f5-4237-9190-012177145e10' = 'Global Administrator'
        '194ae4cb-b126-40b2-bd5b-6091b380977d' = 'Security Administrator'
        '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3' = 'Application Administrator'
        'e8611ab8-c189-46e8-94e1-60213ab1f814' = 'Privileged Role Administrator'
        '29232cdf-9323-42fd-ade2-1d097af3e4de' = 'Exchange Administrator'
        'b1be1c3e-b65d-4f19-8427-f6fa0d97feb9' = 'Conditional Access Administrator'
        'f28a1f50-f6e7-4571-818b-6a12f2af6b6c' = 'SharePoint Administrator'
        'fe930be7-5e62-47db-91af-98c3a49a38b1' = 'User Administrator'
        '729827e3-9c14-49f7-bb1b-9608f156bbb8' = 'Helpdesk Administrator'
        '966707d0-3269-4727-9be2-8c3a10f19b9d' = 'Password Administrator'
        'b0f54661-2d74-4c50-afa3-1ec803f12efe' = 'Billing Administrator'
        '7be44c8a-adaf-4e2a-84d6-ab2649e08a13' = 'Privileged Authentication Administrator'
        '158c047a-c907-4556-b7ef-446551a6b5f7' = 'Cloud Application Administrator'
        'c4e39bd9-1100-46d3-8c65-fb160da0071f' = 'Authentication Administrator'
        '9f06204d-73c1-4d4c-880a-6edb90606fd8' = 'Azure AD Joined Device Local Administrator'
        '17315797-102d-40b4-93e0-432062caca18' = 'Compliance Administrator'
        '4a5d8f65-41da-4de4-8968-e035b65339cf' = 'Reports Reader'
        '75941009-915a-4869-abe7-691bff18279e' = 'Skype for Business Administrator'
    }

    $Ids = switch ($Set) {
        'GlobalAdministrator' { @('62e90394-69f5-4237-9190-012177145e10') }
        'CisaHighlyPrivileged' {
            @(
                '62e90394-69f5-4237-9190-012177145e10',
                '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3',
                '29232cdf-9323-42fd-ade2-1d097af3e4de',
                '729827e3-9c14-49f7-bb1b-9608f156bbb8',
                '966707d0-3269-4727-9be2-8c3a10f19b9d',
                'b0f54661-2d74-4c50-afa3-1ec803f12efe'
            )
        }
        default { @($Catalog.Keys) }
    }

    if ($WithNames.IsPresent) {
        return @(foreach ($Id in $Ids) {
                [PSCustomObject]@{ Id = $Id; DisplayName = $Catalog[$Id] }
            })
    }

    return @($Ids)
}
