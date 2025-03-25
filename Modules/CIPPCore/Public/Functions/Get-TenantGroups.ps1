function Get-TenantGroups {
    <#
    .SYNOPSIS
        Get tenant groups
    .DESCRIPTION
        Get tenant groups from Azure Table Storage
    .PARAMETER GroupId
        The group id to filter on
    .PARAMETER TenantFilter
        The tenant filter to apply to get the groups for a specific tenant
    #>
    [CmdletBinding()]
    param(
        $GroupId,
        $TenantFilter
    )

    $GroupTable = Get-CippTable -tablename 'TenantGroups'
    $MembersTable = Get-CippTable -tablename 'TenantGroupMembers'

    if ($TenantFilter -and $TenantFilter -ne 'allTenants') {
        $TenantParams = @{
            TenantFilter  = $TenantFilter
            IncludeErrors = $true
        }
    } else {
        $TenantParams = @{
            IncludeErrors = $true
        }
    }
    $Tenants = Get-Tenants @TenantParams

    if ($GroupFilter) {
        $Groups = Get-CIPPAzDataTableEntity @GroupTable -Filter "RowKey eq '$GroupFilter'"
        $AllMembers = Get-CIPPAzDataTableEntity @MembersTable -Filter "GroupId eq '$GroupFilter'"
    } else {
        $Groups = Get-CIPPAzDataTableEntity @GroupTable
        $AllMembers = Get-CIPPAzDataTableEntity @MembersTable
    }

    if (!$Groups) {
        return @()
    }

    if ($TenantFilter -and $TenantFilter -ne 'allTenants') {
        $Memberships = $AllMembers | Where-Object { $_.customerId -eq $Tenants.customerId }
        foreach ($Group in $Memberships) {
            $Group = $Groups | Where-Object { $_.RowKey -eq $Group.GroupId }
            if ($Group) {
                [PSCustomObject]@{
                    Id          = $Group.RowKey
                    Name        = $Group.Name
                    Description = $Group.Description
                }
            }
        }
    } else {
        $Groups | ForEach-Object {
            $Group = $_
            $Members = $AllMembers | Where-Object { $_.GroupId -eq $Group.RowKey }
            if (!$Members) {
                $Members = @()
            }

            $Members = $Members | ForEach-Object {
                $Member = $_
                $Tenant = $Tenants | Where-Object { $Member.customerId -eq $_.customerId }
                if ($Tenant) {
                    @{
                        customerId        = $Tenant.customerId
                        displayName       = $Tenant.displayName
                        defaultDomainName = $Tenant.defaultDomainName
                    }
                }
            }
            if (!$Members) {
                $Members = @()
            }

            [PSCustomObject]@{
                Id          = $Group.RowKey
                Name        = $Group.Name
                Description = $Group.Description
                Members     = @($Members)
            }
        }
    }
}
