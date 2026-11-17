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
        Critical            - the four roles that decide who else is privileged: Global, Privileged Role,
                              Privileged Authentication and Conditional Access Administrator.
        GlobalAdministrator - only Global Administrator.
        EntraPrivileged     - every built-in role Entra flags isPrivileged; what sensitive actions on users are gated on.

    .PARAMETER WithNames
        Return objects with Id and DisplayName instead of bare ids, for callers that need a
        name fallback when the tenant's role definitions are not at hand (cached AllTenants views).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Privileged', 'CisaHighlyPrivileged', 'GlobalAdministrator', 'Critical', 'EntraPrivileged')]
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
        'Critical' {
            @(
                '62e90394-69f5-4237-9190-012177145e10',
                'e8611ab8-c189-46e8-94e1-60213ab1f814',
                '7be44c8a-adaf-4e2a-84d6-ab2649e08a13',
                'b1be1c3e-b65d-4f19-8427-f6fa0d97feb9'
            )
        }
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
        'EntraPrivileged' {
            @(
                '62e90394-69f5-4237-9190-012177145e10', # Global Administrator
                'fe930be7-5e62-47db-91af-98c3a49a38b1', # User Administrator
                '729827e3-9c14-49f7-bb1b-9608f156bbb8', # Helpdesk Administrator
                '4ba39ca4-527c-499a-b93d-d9b492c50246', # Partner Tier1 Support
                'e00e864a-17c5-4a4b-9c06-f5b95a8d5bd8', # Partner Tier2 Support
                '9360feb5-f418-4baa-8175-e2a00bac4301', # Directory Writers
                '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3', # Application Administrator
                'cf1c38e5-3621-4004-a7cb-879624dced7c', # Application Developer
                '5d6b6bb7-de71-4623-b4af-96380a352509', # Security Reader
                '194ae4cb-b126-40b2-bd5b-6091b380977d', # Security Administrator
                'e8611ab8-c189-46e8-94e1-60213ab1f814', # Privileged Role Administrator
                '3a2c62db-5318-420d-8d74-23affee5d9d5', # Intune Administrator
                '158c047a-c907-4556-b7ef-446551a6b5f7', # Cloud Application Administrator
                'b1be1c3e-b65d-4f19-8427-f6fa0d97feb9', # Conditional Access Administrator
                '7698a772-787b-4ac8-901f-60d6b08affd2', # Cloud Device Administrator
                'c4e39bd9-1100-46d3-8c65-fb160da0071f', # Authentication Administrator
                '7be44c8a-adaf-4e2a-84d6-ab2649e08a13', # Privileged Authentication Administrator
                'aaf43236-0c0d-4d5f-883a-6955382ac081', # B2C IEF Keyset Administrator
                'be2f45a1-457d-42af-a067-6ec1fa63bc45', # External Identity Provider Administrator
                '5f2222b1-57c3-48ba-8ad5-d4759f1fde6f', # Security Operator
                'f2ef992c-3afb-46b9-b7cf-a126ee74c451', # Global Reader
                '966707d0-3269-4727-9be2-8c3a10f19b9d', # Password Administrator
                '8ac3fc64-6eca-42ea-9e69-59f4c7b60eb2', # Hybrid Identity Administrator
                '8329153b-31d0-4727-b945-745eb3bc5f31', # Domain Name Administrator
                'd2562ede-74db-457e-a7b6-544e236ebb61', # AI Administrator
                '1fe13547-53f6-408d-ac04-7f8eed167b38', # AI Reader
                '45d8d3c5-c802-45c6-b32a-1d70b5e1e86e', # Identity Governance Administrator
                '25a516ed-2fa0-40ea-a2d0-12923a21473a', # Authentication Extensibility Administrator
                '59d46f88-662b-457b-bceb-5c3809e5908f', # Lifecycle Workflows Administrator
                '422218e4-db15-4ef9-bbe0-8afb41546d79', # Attribute Provisioning Reader
                'ecb2c6bf-0ab6-418e-bd87-7986f8d63bbe', # Attribute Provisioning Administrator
                '0b00bede-4072-4d22-b441-e7df02a1ef63', # Authentication Extensibility Password Administrator
                'db506228-d27e-4b7d-95e5-295956d6615f', # Agent ID Administrator
                '1981f584-96e9-4a6f-95b0-f522373f8fae', # Tenant Governance Administrator
                '58f930cc-fcf4-4152-852c-1d7dbf502139'  # Entra SOC Identity Responder
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
