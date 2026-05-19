function Push-UpdateDynamicTenantGroup {
    <#
    .SYNOPSIS
    Push an update to a Dynamic Tenant Group
    .FUNCTIONALITY
    Entrypoint
    #>

    [CmdletBinding()]
    param ($Item)

    Write-Information "Pushing update to Dynamic Tenant Group: $($Item.Name) (ID: $($Item.Id))"
    Update-CIPPDynamicTenantGroups -GroupId $Item.Id
}
