function Get-HuduMagicDashAttentionItems {
    <#
        .SYNOPSIS
        Lists what needs a human on a tenant, from a Get-HuduMagicDashViewModel model.

        .DESCRIPTION
        Returns plain sentences; **text** marks emphasis. License and Global Administrator
        thresholds are the ones the model was built with.
    #>
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Model)

    $m = $Model
    $Items = [System.Collections.Generic.List[string]]::new()
    $Count = { param([int]$n, $One, $Many) if ($n -eq 1) { "1 $One" } else { "$n $Many" } }

    $Full = @($m.Licenses.Items | Where-Object { $_.IsFull } | ForEach-Object { $_.Name } | Sort-Object)
    if ($Full.Count) { $Items.Add("**$(& $Count $Full.Count 'license is' 'licenses are')** fully assigned: $($Full -join ', ')") }
    $Near = @($m.Licenses.Items | Where-Object { $_.IsNearFull } | Sort-Object { $_.Name } | ForEach-Object { "$($_.Name) ($($_.PctText))" })
    if ($Near.Count) { $Items.Add("**$(& $Count $Near.Count 'license is' 'licenses are')** nearly fully assigned: $($Near -join ', ')") }
    $Ga = @($m.Roles.GlobalAdmins).Count
    $GaSp = @($m.Roles.GlobalAdmins | Where-Object { $_.IsServicePrincipal }).Count
    if ($Ga -ge $m.Roles.GlobalAdminWarnAt) {
        $Sp = if ($GaSp) { " ($(& $Count $GaSp 'service principal' 'service principals'))" } else { '' }
        $Items.Add("**$Ga accounts**$Sp hold Global Administrator (Microsoft recommends fewer than $($m.Roles.GlobalAdminWarnAt))")
    }

    , $Items
}
