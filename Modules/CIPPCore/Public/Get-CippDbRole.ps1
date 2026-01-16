function Get-CippDbRole {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [switch]$IncludePrivilegedRoles,

        [Parameter(Mandatory = $false)]
        [switch]$CisaHighlyPrivilegedRoles
    )

    $Roles = New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Roles'

    if ($IncludePrivilegedRoles) {
        $PrivilegedRoleTemplateIds = @(
            '62e90394-69f5-4237-9190-012177145e10',
            '194ae4cb-b126-40b2-bd5b-6091b380977d',
            '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3',
            'e8611ab8-c189-46e8-94e1-60213ab1f814',
            '29232cdf-9323-42fd-ade2-1d097af3e4de',
            'b1be1c3e-b65d-4f19-8427-f6fa0d97feb9',
            'f28a1f50-f6e7-4571-818b-6a12f2af6b6c',
            'fe930be7-5e62-47db-91af-98c3a49a38b1',
            '729827e3-9c14-49f7-bb1b-9608f156bbb8',
            '966707d0-3269-4727-9be2-8c3a10f19b9d',
            'b0f54661-2d74-4c50-afa3-1ec803f12efe',
            '7be44c8a-adaf-4e2a-84d6-ab2649e08a13',
            '158c047a-c907-4556-b7ef-446551a6b5f7',
            'c4e39bd9-1100-46d3-8c65-fb160da0071f',
            '9f06204d-73c1-4d4c-880a-6edb90606fd8',
            '17315797-102d-40b4-93e0-432062caca18',
            '4a5d8f65-41da-4de4-8968-e035b65339cf',
            '75941009-915a-4869-abe7-691bff18279e'
        )
        $Roles = $Roles | Where-Object { $PrivilegedRoleTemplateIds -contains $_.RoletemplateId }
    }

    if ($CisaHighlyPrivilegedRoles) {
        $CisaRoleTemplateIds = @(
            '62e90394-69f5-4237-9190-012177145e10',
            '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3',
            '29232cdf-9323-42fd-ade2-1d097af3e4de',
            '729827e3-9c14-49f7-bb1b-9608f156bbb8',
            '966707d0-3269-4727-9be2-8c3a10f19b9d',
            'b0f54661-2d74-4c50-afa3-1ec803f12efe'
        )
        $Roles = $Roles | Where-Object { $CisaRoleTemplateIds -contains $_.RoletemplateId }
    }

    return $Roles
}
