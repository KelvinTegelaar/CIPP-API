function Get-NinjaOneOrgFieldBody {
    <#
        .SYNOPSIS
        Renders one NinjaOne organisation WYSIWYG field (TenantLinks, TenantSummary or UsersSummary) from a plain model.

        .DESCRIPTION
        Built from the documentation kit, then adapted with ConvertTo-CippExtensionNinjaOneHtml. Declarations the
        NinjaOne sanitiser drops are rewritten or removed so the stored HTML is what renders. Every model value is
        encoded by the building blocks; colours that are not hex values fall back to the tone colour.

        .PARAMETER Model
        TenantLinks: Portals, CippActions (lists of @{ Label; Url; Tip }).
        TenantSummary: Tiles, Header, Details, Licenses, Devices, Standards, SecureScore, Users (see Invoke-NinjaOneTenantSync).
        UsersSummary: Users (list), Total, Url.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('TenantLinks', 'TenantSummary', 'UsersSummary')][string]$Field,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Model,
        [Nullable[datetime]]$SyncedAt,
        [cultureinfo]$Culture = [cultureinfo]::GetCultureInfo('en-GB'),
        [TimeZoneInfo]$TimeZone = [TimeZoneInfo]::Utc
    )

    $m = $Model
    $TableStyle = Get-CippExtensionUiTableStyle
    $Th = $TableStyle.Th
    $Td = $TableStyle.Td
    $Table = $TableStyle.Table
    $Inv = [cultureinfo]::InvariantCulture
    $Muted = '<span style="opacity:.55">&ndash;</span>'
    # A card may be a string or @{ Html; Class } to take its own column width
    $Columns = {
        param($Cards, $Classes = 'col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex')
        $Cells = @(foreach ($c in $Cards) {
                $Html = if ($c -is [System.Collections.IDictionary]) { $c.Html } else { $c }
                $Class = if ($c -is [System.Collections.IDictionary]) { "$($c.Class) col-md-12 col-sm-12 d-flex" } else { $Classes }
                if ($Html) { "<div class=`"$Class`">$($Html -replace '^<div ', '<div class="flex-grow-1" ')</div>" }
            }) -join ''
        "<div class=`"row g-3`" style=`"margin-top:0`">$Cells</div>"
    }
    $Open = { param($Url, $Tip) if ($Url) { New-CippExtensionUiLink -Url $Url -Label 'Open' -Tip $Tip -Variant button } }
    # A bare icon link for narrow table columns, where a labelled button would wrap
    $IconLink = { param($Url, $Tip) if ("$Url" -match '^https?://') { "<a href=`"$(ConvertTo-CippExtensionUiText $Url)`" target=`"_blank`" title=`"$(ConvertTo-CippExtensionUiText $Tip)`"><i class=`"fas fa-arrow-up-right-from-square`"></i></a>" } }
    $Colour = { param($Item) if ("$($Item.Colour)" -match '^#[0-9A-Fa-f]{3,8}$') { $Item.Colour } else { (Get-CippExtensionUiTone $Item.Tone).Bar } }
    $Pct = { param($Part, $Whole) [math]::Round(([double]$Part / [double]$Whole) * 100, 2).ToString($Inv) }
    $Date = {
        param($Value)
        $Utc = ConvertTo-CippExtensionUiDate $Value
        if ($Utc) { [TimeZoneInfo]::ConvertTimeFromUtc($Utc, $TimeZone).ToString((Get-CippExtensionUiDatePattern $Culture), $Culture) } else { "$Value" }
    }
    # NinjaOne drops background fills, so bars and swatches are drawn with borders
    $Bar = {
        param($PctText, $Tone)
        $BarColour = if ($Tone -in 'ok', 'neutral') { '#f77f00' } else { (Get-CippExtensionUiTone $Tone).Bar }
        "<div style=`"height:8px;border:1px solid rgba(128,128,128,.4);border-radius:4px`"><div style=`"width:$(ConvertTo-CippExtensionUiText $PctText)%;height:8px;border:4px solid $BarColour;box-sizing:border-box;border-radius:4px`"></div></div>"
    }
    # Stacked inline-block segments with no whitespace between them; each legend entry keeps to one line
    $Chart = {
        param($Title, $Items)
        $Items = @($Items | Sort-Object { [double]$_.Amount } -Descending -Stable)
        $Total = ($Items | ForEach-Object { [double]$_.Amount } | Measure-Object -Sum).Sum
        $Segments = if ($Total -gt 0) {
            -join @(foreach ($i in $Items) {
                    if ([double]$i.Amount -gt 0) { "<div style=`"display:inline-block;vertical-align:top;width:$(& $Pct $i.Amount $Total)%;height:8px;border:4px solid $(& $Colour $i);box-sizing:border-box`"></div>" }
                })
        }
        $Track = if ($Segments) { "<div style=`"height:8px;margin:8px 0 4px;white-space:nowrap;font-size:0`">$Segments</div>" } else { "<div style=`"margin-top:4px;font-size:12px;opacity:.7`">None</div>" }
        $Legend = @(foreach ($i in $Items) {
                "<span style=`"display:inline-block;white-space:nowrap;margin:4px 14px 0 0;font-size:12px`"><span style=`"display:inline-block;vertical-align:middle;width:10px;height:10px;border:5px solid $(& $Colour $i);box-sizing:border-box;border-radius:2px;margin-right:6px`"></span>$(ConvertTo-CippExtensionUiText $i.Label) <span style=`"font-weight:600`">$(ConvertTo-CippExtensionUiText $i.Amount)</span></span>"
            }) -join ' '
        New-CippExtensionUiSection -Title $Title -Count "$Total" -Body "$Track<div>$Legend</div>"
    }
    $Grid = {
        param($Head, $Rows)
        $Cells = -join @(foreach ($h in $Head) { "<th style=`"$Th;white-space:nowrap`">$(ConvertTo-CippExtensionUiText $h)</th>" })
        "<table style=`"$Table`"><tbody><tr>$Cells</tr>$Rows</tbody></table>"
    }

    $Html = switch ($Field) {
        'TenantLinks' {
            $Portals = @(foreach ($i in $m.Portals) { New-CippExtensionUiLink -Url $i.Url -Label $i.Label -Tip $i.Tip -Variant button }) -join ' '
            $Actions = @(foreach ($i in $m.CippActions) { New-CippExtensionUiLink -Url $i.Url -Label $i.Label -Tip $i.Tip -Variant cipp }) -join ' '
            & $Columns @(
                (New-CippExtensionUiCard -Title 'Portals' -Icon 'cogs' -Body "<div>$Portals</div>"),
                (New-CippExtensionUiCard -Title 'CIPP Actions' -Icon 'shield-alt' -Body "<div>$Actions</div>")
            ) 'col-lg-6 col-md-12 col-sm-12 d-flex'
        }

        'TenantSummary' {
            # Posture tiles
            $Tiles = foreach ($t in $m.Tiles) {
                $ToneColour = if ($t.Tone -in 'ok', 'err', 'warn', 'info') { ";color:$((Get-CippExtensionUiTone $t.Tone).Bar)" } else { '' }
                $Value = if ($t.Icon) { "<i class=`"fas fa-$($t.Icon -replace '[^a-z0-9-]', '')`"></i>" } else { ConvertTo-CippExtensionUiText $t.Value }
                $Note = if ($t.Note) { "<div style=`"margin-top:4px;font-size:11px;opacity:.7`">$(ConvertTo-CippExtensionUiText $t.Note)</div>" }
                "<div style=`"border:1px solid rgba(128,128,128,.3);border-radius:6px;padding:12px 14px;box-sizing:border-box`">" +
                "<div style=`"font-size:12px;font-weight:600`">$(New-CippExtensionUiLink -Url $t.Url -Label $t.Label -Tip "Open $($t.Label)" -Variant text)</div>" +
                "<div style=`"margin-top:6px;font-size:20px;font-weight:600;line-height:1.2$ToneColour`">$Value</div>$Note</div>"
            }
            $TilesHtml = if ($Tiles) { & $Columns $Tiles 'col-xl-2 col-lg-3 col-md-4 col-sm-6 d-flex' }

            # Header
            $h = $m.Header
            $Synced = if ($SyncedAt) { New-CippExtensionUiSynced -SyncedAt $SyncedAt -Culture $Culture -TimeZone $TimeZone }
            $Header = "<div style=`"border:1px solid rgba(128,128,128,.3);border-top:3px solid #f77f00;border-radius:6px;padding:14px 16px;box-sizing:border-box;margin-top:12px`">" +
            "<div><span style=`"vertical-align:middle;font-size:18px;font-weight:600;line-height:1.3;margin-right:8px`">$(ConvertTo-CippExtensionUiText $h.TenantName)</span> $(New-CippExtensionUiChip -Text $h.DefaultDomain)</div>" +
            "<div style=`"font-size:13px;opacity:.75`">Microsoft 365 tenant <span style=`"font-size:12px;word-break:break-all`">$(ConvertTo-CippExtensionUiText $h.TenantId)</span></div>$Synced</div>"

            # Tenant details
            $d = $m.Details
            $DomainChips = @(foreach ($i in $d.Domains) { New-CippExtensionUiChip -Text $i }) -join ' '
            $AdminChips = @(foreach ($i in $d.Admins) { New-CippExtensionUiChip -Text $i }) -join ' '
            $Created = if ($d.Created) { & $Date $d.Created }
            $DetailsCard = New-CippExtensionUiCard -Title 'Tenant Details' -Icon 'building' -Body ((New-CippExtensionUiRow -Label 'Creation date' -Value $Created) +
                "<div style=`"padding:10px 0 4px`"><div style=`"font-size:13px;opacity:.7;margin-bottom:4px`">Domains</div><div>$(if ($DomainChips) { $DomainChips } else { $Muted })</div></div>" +
                "<div style=`"padding:6px 0 0`"><div style=`"font-size:13px;opacity:.7;margin-bottom:4px`">Admin users</div><div>$(if ($AdminChips) { $AdminChips } else { $Muted })</div></div>")

            # Licenses
            $Lic = $m.Licenses
            $LicBody = if (@($Lic.Items).Count) {
                $Rows = -join @(foreach ($i in $Lic.Items) {
                        "<tr><td style=`"$Td`">$(ConvertTo-CippExtensionUiText $i.Name)</td><td style=`"$Td;text-align:right`">$(ConvertTo-CippExtensionUiText $i.Active)</td><td style=`"$Td;text-align:right`">$(ConvertTo-CippExtensionUiText $i.Consumed)</td><td style=`"$Td;text-align:right`">$(ConvertTo-CippExtensionUiText $i.Unused)</td></tr>"
                    })
                & $Grid @('License', 'Active', 'Consumed', 'Unused') $Rows
            } else { "<div style=`"font-size:13px;opacity:.7`">No licenses</div>" }
            $LicCard = New-CippExtensionUiCard -Title 'Licenses' -Icon 'key' -Count "$(@($Lic.Items).Count)" -Flag (& $Open $Lic.Url 'Open the license report in CIPP') -Body $LicBody

            # Devices
            $Dev = $m.Devices
            $DevCard = New-CippExtensionUiCard -Title 'Device Details' -Icon 'network-wired' -Flag (& $Open $Dev.Url 'Open devices in CIPP') -Body (-join @(foreach ($c in $Dev.Charts) { & $Chart $c.Title $c.Items }))

            # Standards
            $Std = $m.Standards
            $StdBody = if (@($Std.Items).Count) {
                $Rows = -join @(foreach ($i in $Std.Items) {
                        $Actions = @(foreach ($a in @($i.Actions)) { if ($a) { New-CippExtensionUiChip -Text $a -Small } }) -join ' '
                        "<tr><td style=`"$Td`">$(ConvertTo-CippExtensionUiText $i.Standard)</td><td style=`"$Td`">$(if ($i.Template) { ConvertTo-CippExtensionUiText $i.Template } else { $Muted })</td><td style=`"$Td`">$(if ($Actions) { $Actions } else { $Muted })</td></tr>"
                    })
                & $Grid @('Standard', 'Template', 'Actions') $Rows
            } else { "<div style=`"font-size:13px;opacity:.7`">$(ConvertTo-CippExtensionUiText $(if ($Std.Error) { $Std.Error } else { 'No standards applied' }))</div>" }
            $StdCard = New-CippExtensionUiCard -Title 'CIPP Applied Standards' -Icon 'shield-alt' -Count "$(@($Std.Items).Count)" -Flag (& $Open $Std.Url 'Open standards in CIPP') -Body $StdBody

            # Secure Score
            $Ss = $m.SecureScore
            $SsBody = if ([double]$Ss.Max -gt 0) {
                $ScorePct = & $Pct $Ss.Current $Ss.Max
                $Score = "<div style=`"font-size:13px`"><span style=`"font-size:20px;font-weight:600`">$(ConvertTo-CippExtensionUiText ([double]$ScorePct).ToString($Culture))%</span> <span style=`"opacity:.7`">$(ConvertTo-CippExtensionUiText ([double]$Ss.Current).ToString($Culture)) of $(ConvertTo-CippExtensionUiText ([double]$Ss.Max).ToString($Culture)) points</span></div>" +
                "<div style=`"margin:6px 0 4px`">$(& $Bar $ScorePct 'ok')</div>"
                $ActionRows = -join @(foreach ($i in $Ss.Actions) {
                        $Impact = "+$(([double]$i.Impact).ToString($Culture))%"
                        "<tr><td style=`"$Td`">$(ConvertTo-CippExtensionUiText $i.Action)</td><td style=`"$Td;white-space:nowrap`">$(New-CippExtensionUiChip -Text $Impact -Tone ok -Small -Strong)</td><td style=`"$Td`">$(ConvertTo-CippExtensionUiText $i.Category)</td><td style=`"$Td;white-space:nowrap;text-align:center`">$(& $IconLink $i.Url 'Open this action in Microsoft Defender')</td></tr>"
                    })
                $Score + $(if ($ActionRows) { New-CippExtensionUiSection -Title 'Top recommended actions' -Body (& $Grid @('Recommended action', 'Score impact', 'Category', 'Link') $ActionRows) })
            } else { "<div style=`"font-size:13px;opacity:.7`">No Secure Score data available</div>" }
            $SsCard = New-CippExtensionUiCard -Title 'Secure Score' -Icon 'shield-alt' -Flag (& $Open $Ss.Url 'Open Secure Score in Microsoft Defender') -Body $SsBody

            # Users
            $Usr = $m.Users
            $UsrCard = New-CippExtensionUiCard -Title 'User Details' -Icon 'users' -Flag (& $Open $Usr.Url 'Open users in CIPP') -Body (-join @(foreach ($c in $Usr.Charts) { & $Chart $c.Title $c.Items }))

            # Tables need half the width or their first column wraps word by word
            $Cards = @(
                @{ Html = $DetailsCard; Class = 'col-xl-4 col-lg-6' }
                @{ Html = $LicCard; Class = 'col-xl-8 col-lg-6' }
                @{ Html = $StdCard; Class = 'col-xl-6 col-lg-6' }
                @{ Html = $SsCard; Class = 'col-xl-6 col-lg-6' }
                @{ Html = $DevCard; Class = 'col-xl-6 col-lg-6' }
                @{ Html = $UsrCard; Class = 'col-xl-6 col-lg-6' }
            )
            "<div style=`"overflow:hidden`">$TilesHtml$Header$(& $Columns $Cards)</div>"
        }

        'UsersSummary' {
            $Shown = @($m.Users | Select-Object -First 100)
            $Total = if ($m.Total) { [int]$m.Total } else { @($m.Users).Count }
            $Usage = {
                param($u)
                if (-not $u) { return "<span style=`"opacity:.7`">Not enabled</span>" }
                $Tone = if ([double]$u.Pct -ge 95) { 'err' } elseif ([double]$u.Pct -ge 85) { 'warn' } else { 'ok' }
                "<div style=`"font-size:12px;margin-bottom:4px;white-space:nowrap`">$(ConvertTo-CippExtensionUiText $u.Text)</div>$(& $Bar $u.Pct $Tone)"
            }
            $Rows = -join @(foreach ($u in $Shown) {
                    $Lics = @(foreach ($l in $u.Licenses) { New-CippExtensionUiChip -Text $l -Small }) -join ' '
                    $Devs = -join @(foreach ($d in $u.Devices) {
                            $State = if ($d.Compliant) { "<i class=`"fas fa-check-circle`" style=`"color:$((Get-CippExtensionUiTone ok).Bar);margin-right:6px`"></i>" } else { "<i class=`"fas fa-times-circle`" style=`"color:$((Get-CippExtensionUiTone err).Bar);margin-right:6px`"></i>" }
                            $OsIcon = switch ($d.Os) { 'Windows' { '<i class="fab fa-windows" style="margin-right:6px"></i>' } { $_ -in 'iOS', 'macOS' } { '<i class="fab fa-apple" style="margin-right:6px"></i>' } 'Android' { '<i class="fab fa-android" style="margin-right:6px"></i>' } }
                            $Login = if ($d.LastLogin) { & $Date $d.LastLogin } else { 'Unknown' }
                            "<div style=`"white-space:nowrap`">$State$OsIcon$(New-CippExtensionUiLink -Url $d.Url -Label $d.Name -Tip "Open $($d.Name) in NinjaOne" -Variant text) <span style=`"opacity:.7`">($(ConvertTo-CippExtensionUiText $Login))</span></div>"
                        })
                    $Links = "$(New-CippExtensionUiLink -Url $u.CippUrl -Label 'CIPP' -Tip 'View in CIPP' -Variant cipp) $(New-CippExtensionUiLink -Url $u.EntraUrl -Label 'Entra' -Tip 'View in Entra ID' -Variant button)"
                    "<tr><td style=`"$Td;font-weight:600`">$(ConvertTo-CippExtensionUiText $u.Name)</td><td style=`"$Td`">$(ConvertTo-CippExtensionUiText $u.Upn)</td>" +
                    "<td style=`"$Td`">$(if ($Lics) { $Lics } else { $Muted })</td><td style=`"$Td;width:12%`">$(& $Usage $u.Mailbox)</td><td style=`"$Td;width:12%`">$(& $Usage $u.OneDrive)</td>" +
                    "<td style=`"$Td`">$(if ($Devs) { $Devs } else { $Muted })</td><td style=`"$Td;white-space:nowrap`">$Links</td></tr>"
                })
            $Note = if ($Total -gt 100) {
                "<div style=`"margin-bottom:12px;padding:10px 14px;border-radius:6px;background:rgba(247,144,9,.12);border:1px solid rgba(247,144,9,.5)`">" +
                "<div style=`"font-size:13px;font-weight:600`">$(Get-CippExtensionUiIcon -Name info-circle)$Total users found in Tenant</div>" +
                "<div style=`"margin-top:2px;font-size:13px`">Only the first 100 users are displayed here. To see all users please $(New-CippExtensionUiLink -Url $m.Url -Label 'view users in CIPP' -Tip 'Open users in CIPP' -Variant strong).</div></div>"
            }
            $Body = if ($Rows) { & $Grid @('Name', 'User Principal Name', 'Licenses', 'Mailbox Usage', 'OneDrive Usage', 'Devices (Last Login)', 'Actions') $Rows } else { "<div style=`"font-size:13px;opacity:.7`">No users</div>" }
            "<div style=`"overflow:hidden`">$Note$(New-CippExtensionUiCard -Title 'Users' -Icon 'users' -Count "$Total" -Flag (& $Open $m.Url 'Open users in CIPP') -Body $Body)</div>"
        }
    }

    $Html = ConvertTo-CippExtensionNinjaOneHtml -Html $Html
    # Rewrite what the sanitiser would drop: fills go, muted text turns grey, top rules use longhand borders
    $Html = [regex]::Replace($Html, ' style="([^"]*)"', {
            param($Attr)
            $Decls = @($Attr.Groups[1].Value -split ';' | Where-Object { $_ })
            $HasColour = [bool]($Decls -match '^color:')
            $Out = foreach ($d in $Decls) {
                if ($d -match '^background|^border:0$') { continue }
                if ($d -match '^opacity:') { if (-not $HasColour) { 'color:#8a8f98' }; continue }
                if ($d -match '^border-top:(\S+) (\S+) (.+)$') { "border-width:$($Matches[1]) 0 0;border-style:$($Matches[2]);border-color:$($Matches[3])"; continue }
                $d
            }
            " style=`"$($Out -join ';')`""
        })
    # Titles survive only on links
    [regex]::Replace($Html, '<(?!a )[a-z0-9]+ [^>]*>', { param($Tag) $Tag.Value -replace ' title="[^"]*"', '' })
}
