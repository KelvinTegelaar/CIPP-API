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

    $Roles = Get-CIPPTestData -TenantFilter $TenantFilter -Type 'Roles'

    # The id lists live in Get-CIPPPrivilegedRoleTemplateIds so every "privileged roles" scope in
    # CIPP (tests, PIM pages, standards, alerts) means the same roles.
    if ($IncludePrivilegedRoles) {
        $PrivilegedRoleTemplateIds = Get-CIPPPrivilegedRoleTemplateIds -Set Privileged
        $Roles = $Roles | Where-Object { $PrivilegedRoleTemplateIds -contains $_.RoletemplateId }
    }

    if ($CisaHighlyPrivilegedRoles) {
        $CisaRoleTemplateIds = Get-CIPPPrivilegedRoleTemplateIds -Set CisaHighlyPrivileged
        $Roles = $Roles | Where-Object { $CisaRoleTemplateIds -contains $_.RoletemplateId }
    }

    return $Roles
}
