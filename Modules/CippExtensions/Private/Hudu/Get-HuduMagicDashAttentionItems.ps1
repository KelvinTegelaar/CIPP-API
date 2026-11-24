function Get-HuduMagicDashAttentionItems {
    <#
        .SYNOPSIS
        Lists what needs a human on a tenant, from a Get-HuduMagicDashViewModel model.

        .DESCRIPTION
        Returns plain sentences; **text** marks emphasis. Over-assigned licenses and a missing
        Global Administrator always show; fully assigned, nearly full and many-Global-Administrator
        warnings need -ShowLicenseFull, -ShowLicenseNearFull and -ShowGlobalAdminCount.
        License and Global Administrator thresholds are the ones the model was built with.
    #>
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Model,
        [switch]$ShowLicenseFull,
        [switch]$ShowLicenseNearFull,
        [switch]$ShowGlobalAdminCount
    )

    $m = $Model
    $Items = [System.Collections.Generic.List[string]]::new()
    $Count = { param([int]$n, $One, $Many) if ($n -eq 1) { "1 $One" } else { "$n $Many" } }

    $Over = @($m.Licenses.Items | Where-Object { $_.IsOverAssigned } | Sort-Object { $_.Name } | ForEach-Object { "$($_.Name) ($($_.ConsumedText) of $($_.ActiveText))" })
    if ($Over.Count) { $Items.Add("**$(& $Count $Over.Count 'license is' 'licenses are')** over-assigned (more seats assigned than purchased): $($Over -join ', ')") }
    $Full = @($m.Licenses.Items | Where-Object { $_.IsFull } | ForEach-Object { $_.Name } | Sort-Object)
    if ($Full.Count -and $ShowLicenseFull) { $Items.Add("**$(& $Count $Full.Count 'license is' 'licenses are')** fully assigned: $($Full -join ', ')") }
    $Near = @($m.Licenses.Items | Where-Object { $_.IsNearFull } | Sort-Object { $_.Name } | ForEach-Object { "$($_.Name) ($($_.PctText))" })
    if ($Near.Count -and $ShowLicenseNearFull) { $Items.Add("**$(& $Count $Near.Count 'license is' 'licenses are')** nearly fully assigned: $($Near -join ', ')") }
    $Ga = @($m.Roles.GlobalAdmins).Count
    $GaSp = @($m.Roles.GlobalAdmins | Where-Object { $_.IsServicePrincipal }).Count
    # Raised only when role data came back, and PIM-eligible Global Administrators count as holders.
    $GaEligible = @($m.Roles.Items | Where-Object { $_.IsGlobalAdmin -and $_.Eligible }).Count
    if ($Ga -eq 0 -and -not $GaEligible -and @($m.Roles.Items).Count) { $Items.Add('**No account holds Global Administrator**') }
    if ($ShowGlobalAdminCount -and $Ga -ge $m.Roles.GlobalAdminWarnAt) {
        $Sp = if ($GaSp) { " ($(& $Count $GaSp 'service principal' 'service principals'))" } else { '' }
        $Items.Add("**$Ga accounts**$Sp hold Global Administrator (Microsoft recommends fewer than $($m.Roles.GlobalAdminWarnAt))")
    }

    , $Items
}
