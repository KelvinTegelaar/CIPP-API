function Get-HuduStaleMagicDash {
    <#
        .SYNOPSIS
        Picks the Microsoft 365 Magic Dashes left behind by a tenant rename.

        .DESCRIPTION
        A dash is stale when its title has the Microsoft 365 prefix but is not the current title, and its content
        carries this tenant's ID. A Hudu company can be mapped to several tenants, so the ID check is what keeps
        another tenant's dash safe.
    #>
    param(
        [AllowNull()][object[]]$Dashes,
        [Parameter(Mandatory)][string]$CurrentTitle,
        [Parameter(Mandatory)][string]$TenantId
    )
    if ([string]::IsNullOrWhiteSpace($TenantId)) { return }
    foreach ($Dash in @($Dashes | Where-Object { $_ })) {
        $Title = [string]$Dash.title
        if ($Title -like 'Microsoft 365 - *' -and $Title -ne $CurrentTitle -and ([string]$Dash.content).Contains($TenantId, [System.StringComparison]::OrdinalIgnoreCase)) {
            $Dash
        }
    }
}
