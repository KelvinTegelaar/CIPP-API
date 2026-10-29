function Get-HuduMagicDashBody {
    <#
        .SYNOPSIS
        Renders the tenant Magic Dash content from a Get-HuduMagicDashViewModel model.

        .DESCRIPTION
        Inline styles only, no fixed text colours, so one output reads in Hudu light and dark. Every model value
        is encoded by the building blocks. The tenant ID is always rendered.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Model,
        [Nullable[datetime]]$SyncedAt,
        [cultureinfo]$Culture = [cultureinfo]::GetCultureInfo('en-GB'),
        [TimeZoneInfo]$TimeZone = [TimeZoneInfo]::Utc
    )

    $m = $Model
    # Hudu strips the CSS gap property and its mobile app ignores flex and margins on inline-blocks,
    # so rows are inline flow with margins plus a literal space between inline-block items
    $TableStyle = Get-CippExtensionUiTableStyle
    $Th = $TableStyle.Th
    $Td = $TableStyle.Td
    $Table = $TableStyle.Table
    # Hudu's mobile app ignores grid and stacks the cells, which suits a phone
    $Columns = {
        param($Cards, $Basis)
        $Cells = @(foreach ($c in $Cards) { if ($c) { "<div style=`"min-width:0;margin:6px`">$c</div>" } }) -join ''
        "<div style=`"display:grid;grid-template-columns:repeat(auto-fit,minmax($($Basis)px,1fr));margin:6px -6px -6px`">$Cells</div>"
    }
    $Muted = '<span style="opacity:.55">&ndash;</span>'

    # Header card
    $Name = ConvertTo-CippExtensionUiText $m.Header.TenantName
    $Synced = if ($SyncedAt) { New-CippExtensionUiSynced -SyncedAt $SyncedAt -Culture $Culture -TimeZone $TimeZone }
    $PortalLinks = @(foreach ($i in $m.Links) { New-CippExtensionUiLink -Url $i.Url -Label $i.Title -Tip $i.Tip -Variant button }) -join ' '
    $Header = "<div style=`"border:1px solid rgba(128,128,128,.3);border-top:3px solid #f77f00;border-radius:6px;padding:14px 16px 8px;box-sizing:border-box`">" +
    "<div><span style=`"vertical-align:middle;font-size:18px;font-weight:600;line-height:1.3;margin-right:8px`">$Name</span> $(New-CippExtensionUiChip -Text $m.Header.DefaultDomain -Title 'Default domain')</div>" +
    "<div style=`"font-size:13px;opacity:.75`">Microsoft 365 tenant <code style=`"font-size:11px;word-break:break-all`">$(ConvertTo-CippExtensionUiText $m.Header.TenantId)</code></div>$Synced" +
    "<div style=`"margin-top:10px;padding-top:12px;border-top:1px solid rgba(128,128,128,.2)`"><span style=`"display:inline-block;vertical-align:middle;font-size:12px;opacity:.7;margin:0 8px 6px 0`">Portals</span> $PortalLinks</div></div>"

    # Stat tiles
    $Tile = {
        param($Title, $Icon, $Stat)
        "<div style=`"border-radius:6px;background:rgba(128,128,128,.09);padding:12px 14px;box-sizing:border-box`"><div>$(Get-CippExtensionUiIcon -Name $Icon -Badge)" +
        "<span style=`"vertical-align:middle;font-size:12px;font-weight:600;letter-spacing:1px;text-transform:uppercase;opacity:.7`">$(ConvertTo-CippExtensionUiText $Title)</span></div><div style=`"margin-top:6px;font-size:20px;font-weight:600;line-height:1.2`">$(ConvertTo-CippExtensionUiText $Stat.Total)</div><div style=`"font-size:12px;opacity:.8;margin-top:6px`">$(ConvertTo-CippExtensionUiText $Stat.Foot)</div></div>"
    }
    $Tiles = & $Columns @((& $Tile 'Licensed users' 'users' $m.Stats.Users), (& $Tile 'License SKUs' 'key' $m.Stats.Licenses), (& $Tile 'Global Administrators' 'user-shield' $m.Stats.Admins), (& $Tile 'Verified domains' 'globe' $m.Stats.Domains)) 200

    # Needs attention
    $AttentionHtml = if ($m.Attention.Count) {
        $Items = @(foreach ($a in $m.Attention) { "<div style=`"margin-top:4px`">$(ConvertTo-CippExtensionUiRich $a)</div>" }) -join ''
        "<div style=`"margin-top:12px;padding:10px 14px;border-radius:6px;background:rgba(247,144,9,.12);border:1px solid rgba(247,144,9,.5)`">" +
        "<div style=`"font-size:13px;font-weight:600`">$(Get-CippExtensionUiIcon -Name Warning)Needs attention <span style=`"font-weight:400;opacity:.7;margin-left:6px`">$($m.Attention.Count)</span></div>" +
        "<div style=`"margin-top:2px;font-size:13px`">$Items</div></div>"
    }

    # Basic info and role holders
    $DomainChips = @(foreach ($d in $m.Domains) { New-CippExtensionUiChip -Text $d }) -join ' '
    $Basic = New-CippExtensionUiCard -Title 'Basic info' -Icon 'info-circle' -Body ((New-CippExtensionUiRow -Label 'Tenant' -Value $m.Header.TenantName) +
        "<tr><td colspan=`"2`" style=`"$($TableStyle.RowCell);$($TableStyle.RowSep);padding:7px 0`"><div style=`"opacity:.7;margin-bottom:2px`">Tenant ID</div><code style=`"font-size:11px;word-break:break-all`">$(ConvertTo-CippExtensionUiText $m.Header.TenantId)</code></td></tr>" +
        (New-CippExtensionUiRow -Label 'Default domain' -Value $m.Header.DefaultDomain) +
        "<tr><td colspan=`"2`" style=`"$($TableStyle.RowCell);$($TableStyle.RowSep);padding:7px 0`"><div style=`"opacity:.7;margin-bottom:4px`">Verified domains</div><div>$DomainChips</div></td></tr>")

    $PrincipalRows = {
        param($List)
        @(foreach ($i in $List) {
                $Ga = if ($i.IsGlobalAdmin) { ' ' + (New-CippExtensionUiChip -Text 'Global Admin' -Tone warn -Strong -Small) }
                $NameTip = if ($i.Identifier) { " title=`"$(ConvertTo-CippExtensionUiText $i.Identifier)`"" } else { '' }
                "<tr><td style=`"$Td;padding-left:0`"$NameTip>$(if ($i.Kind) { Get-CippExtensionUiIcon -Name $i.Kind })$(ConvertTo-CippExtensionUiText $i.Name)$Ga</td><td style=`"$Td;padding-right:0;white-space:nowrap;text-align:right`" title=`"$(ConvertTo-CippExtensionUiText $i.RoleTip)`">$(ConvertTo-CippExtensionUiText $i.RoleLabel)</td></tr>"
            }) -join ''
    }
    $Holders = if ($m.Roles.PrincipalCount) {
        $More = if ($m.Roles.More.Count) {
            New-CippExtensionUiDetails -Summary 'Everyone else' -Count $m.Roles.More.Count -Style 'margin-top:8px;padding-top:8px;border-top:1px solid rgba(128,128,128,.2)' -Body "<table style=`"$Table`"><tbody>$(& $PrincipalRows $m.Roles.More)</tbody></table>"
        }
        New-CippExtensionUiCard -Title 'Role holders' -Icon 'user-shield' -Count $m.Roles.PrincipalCount -Right 'By number of directory roles' -Body "<table style=`"$Table`"><tbody>$(& $PrincipalRows $m.Roles.Top)</tbody></table>$More"
    }
    $Two = & $Columns @($Basic, $Holders) 400

    # Licenses
    $LicCard = if ($m.Licenses.Count) {
        $Rows = @(foreach ($i in $m.Licenses.InUse) {
                $Full = if ($i.IsFull) { ' ' + (New-CippExtensionUiChip -Text 'Full' -Tone warn -Strong -Small -Title 'Every license is assigned') }
                "<tr><td style=`"$Td;padding-left:0`">$(ConvertTo-CippExtensionUiText $i.Name)$Full</td>" +
                "<td style=`"$Td;width:32%;vertical-align:middle`"><div style=`"font-size:11px;opacity:.7;margin-bottom:2px`">$(ConvertTo-CippExtensionUiText $i.PctText)</div>$(New-CippExtensionUiBar -Pct $i.Pct -Tone $i.Tone -Title $i.Tip -Height 6)</td>" +
                "<td style=`"$Td;white-space:nowrap;text-align:right`">$(ConvertTo-CippExtensionUiText $i.ConsumedText) <span style=`"opacity:.65`">of $(ConvertTo-CippExtensionUiText $i.ActiveText)</span></td>" +
                "<td style=`"$Td;padding-right:0;white-space:nowrap;text-align:right;opacity:.75`">$(ConvertTo-CippExtensionUiText $i.UnusedText) free</td></tr>"
            }) -join ''
        $InUseTable = if ($Rows) { "<table style=`"$Table`"><tbody>$Rows</tbody></table>" }
        $UnassignedHtml = if ($m.Licenses.Unassigned.Count) {
            $Chips = @(foreach ($i in $m.Licenses.Unassigned) { New-CippExtensionUiChip -Text $i.Name -Suffix $i.ActiveText }) -join ' '
            New-CippExtensionUiDetails -Summary 'Purchased but not assigned' -Count $m.Licenses.Unassigned.Count -Style 'margin-top:8px;padding-top:10px;border-top:1px solid rgba(128,128,128,.2)' -Body "<div style=`"margin-top:8px`">$Chips</div>"
        }
        New-CippExtensionUiCard -Title 'Licenses' -Icon 'key' -Count $m.Licenses.Count -Right 'Assigned of purchased' -Spaced -Body "$InUseTable$UnassignedHtml"
    }

    # All roles, collapsed
    $RolesCard = if ($m.Roles.Items.Count) {
        $Rows = @(foreach ($i in $m.Roles.Items) {
                $Members = @(foreach ($n in $i.Members) { New-CippExtensionUiChip -Text $n.Name -Icon $n.Kind }) -join ' '
                $Eligible = if ($i.Eligible) { "<span style=`"opacity:.7;margin-right:4px`">Eligible:</span> $(New-CippExtensionUiChip -Text $i.Eligible -Tone info)" }
                $Assigned = if ($Members -or $Eligible) { (@($Members, $Eligible) | Where-Object { $_ }) -join ' ' } else { $Muted }
                "<tr><td style=`"$Td;padding-left:0`">$(ConvertTo-CippExtensionUiText $i.Name)</td><td style=`"$Td;padding-right:0`">$Assigned</td></tr>"
            }) -join ''
        "<div style=`"border:1px solid rgba(128,128,128,.3);border-radius:6px;padding:14px 16px;box-sizing:border-box;margin-top:12px`">" +
        (New-CippExtensionUiDetails -Summary 'Assigned roles' -Count $m.Roles.Items.Count -Style 'padding:0' -Icon 'list' -Body "<table style=`"$Table;margin-top:8px`"><tbody>$Rows</tbody></table>") + '</div>'
    }

    # Licensed users
    $PeopleCard = if ($m.People.Count -or $m.Resource.Count) {
        $Rows = @(foreach ($i in $m.People) {
                $UserName = if ($i.Url) { New-CippExtensionUiLink -Url $i.Url -Label $i.Name -Tip "Open $($i.Name) in Hudu" -Variant strong } else { "<span style=`"font-weight:600`">$(ConvertTo-CippExtensionUiText $i.Name)</span>" }
                $Devices = @(foreach ($d in $i.Devices) { New-CippExtensionUiChip -Text $d.Name -Title $d.Tip }) -join ' '
                "<tr><td style=`"$Td;padding-left:0`">$UserName<div style=`"font-size:12px;opacity:.7`">$(ConvertTo-CippExtensionUiText $i.Address)</div></td>" +
                "<td style=`"$Td;white-space:nowrap`">$(New-CippExtensionUiChip -Text $i.LicenseLabel -Title $i.LicenseTip)</td>" +
                "<td style=`"$Td`">$(if ($Devices) { $Devices } else { $Muted })</td>" +
                "<td style=`"$Td;padding-right:0;white-space:nowrap`">$(New-CippExtensionUiLink -Url $i.EntraUrl -Label 'Entra' -Tip 'Open in Entra ID' -Variant text)<span style=`"margin-left:6px`"> </span>$(New-CippExtensionUiLink -Url $i.AdminUrl -Label 'M365' -Tip 'Open in the Microsoft 365 admin center' -Variant text)</td></tr>"
            }) -join ''
        $PeopleTable = if ($Rows) { "<table style=`"$Table`"><tbody><tr><th style=`"$Th;padding-left:0`">Person</th><th style=`"$Th`">Licenses</th><th style=`"$Th`">Devices</th><th style=`"$Th;padding-right:0`">Open in</th></tr>$Rows</tbody></table>" }
        $ResourceHtml = if ($m.Resource.Count) {
            New-CippExtensionUiDetails -Summary 'Resource accounts' -Count $m.Resource.Count -Style 'margin-top:8px;padding-top:10px;border-top:1px solid rgba(128,128,128,.2)' -Body "<div style=`"font-size:12px;line-height:1.8;margin-top:8px;opacity:.9`">$((@(foreach ($r in $m.Resource) { ConvertTo-CippExtensionUiText $r }) -join ' &middot; '))</div>"
        }
        New-CippExtensionUiCard -Title 'Licensed users' -Icon 'id-card' -Count $m.People.Count -Right 'People first; resource accounts are grouped below' -Spaced -Body "$PeopleTable$ResourceHtml"
    }

    "<div style=`"overflow:hidden`">$Header$AttentionHtml$Tiles$Two$LicCard$RolesCard$PeopleCard</div>"
}
