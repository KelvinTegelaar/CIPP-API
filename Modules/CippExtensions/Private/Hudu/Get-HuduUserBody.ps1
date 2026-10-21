function Get-HuduUserBody {
    <#
        .SYNOPSIS
        Renders the Microsoft 365 rich-text field of a Hudu People asset from a Get-HuduUserViewModel model.

        .DESCRIPTION
        Inline styles only, no fixed text colours, so one output reads in Hudu light and dark. Every model value
        is encoded by the building blocks. Sections without data are left out.

        .PARAMETER SyncedAt
        Shown in the header when given.
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
    $TableStyle = Get-HuduUiTableStyle
    $Th = $TableStyle.Th
    $Td = $TableStyle.Td
    $Table = $TableStyle.Table
    $Sep = '<span style="display:inline-block;vertical-align:middle;width:1px;height:20px;background:rgba(128,128,128,.4);margin:0 8px 6px 2px"></span>'
    $LinkLabel = { param($t) "<span style=`"display:inline-block;vertical-align:middle;font-size:12px;opacity:.7;margin:0 8px 6px 0`">$t</span>" }
    $Chips = { param($Items) (@(foreach ($i in $Items) { New-HuduUiChip -Text $i }) -join ' ') }
    # Hudu's mobile app ignores grid and stacks the cells, which suits a phone
    $Columns = {
        param($Cards, $Basis)
        $Cells = @(foreach ($c in $Cards) { if ($c) { "<div style=`"min-width:0;margin:6px`">$c</div>" } }) -join ''
        "<div style=`"display:grid;grid-template-columns:repeat(auto-fit,minmax($($Basis)px,1fr));margin:6px -6px -6px`">$Cells</div>"
    }

    # Header card
    $LinkHtml = [System.Collections.Generic.List[string]]::new()
    $LinkHtml.Add((& $LinkLabel 'Microsoft'))
    foreach ($i in $m.Links.Microsoft) { $LinkHtml.Add((New-HuduUiLink -Url $i.Url -Label $i.Label -Tip $i.Tip -Variant button)) }
    if ($m.Links.Cipp.Count) {
        $LinkHtml.Add($Sep); $LinkHtml.Add((& $LinkLabel 'CIPP'))
        foreach ($i in $m.Links.Cipp) { $LinkHtml.Add((New-HuduUiLink -Url $i.Url -Label $i.Label -Tip $i.Tip -Variant cipp)) }
    }
    if ($m.Links.Psa.Count) {
        $LinkHtml.Add($Sep); $LinkHtml.Add((& $LinkLabel 'PSA'))
        foreach ($i in $m.Links.Psa) { $LinkHtml.Add((New-HuduUiLink -Url $i.Url -Label $i.Label -Tip $i.Tip -Variant button)) }
    }
    $Name = ConvertTo-HuduUiText $m.Header.DisplayName
    $Sub = (@($m.Header.Upn, $m.Header.JobTitle) | Where-Object { $_ } | ForEach-Object { ConvertTo-HuduUiText $_ }) -join ' &middot; '
    $Synced = if ($SyncedAt) { New-HuduUiSynced -SyncedAt $SyncedAt -Culture $Culture -TimeZone $TimeZone }
    $HeaderCard = "<div style=`"border:1px solid rgba(128,128,128,.3);border-top:3px solid #f77f00;border-radius:6px;padding:14px 16px 8px;box-sizing:border-box`">" +
    "<div><span title=`"Initials for $Name`" style=`"display:inline-block;vertical-align:middle;width:44px;height:44px;line-height:44px;text-align:center;border-radius:50%;background:rgba(247,127,0,.16);border:1px solid rgba(247,127,0,.55);font-weight:600;font-size:15px;overflow:hidden;margin:0 12px 6px 0`">$(ConvertTo-HuduUiText $m.Header.Initials)</span> " +
    "<span style=`"vertical-align:middle;font-size:18px;font-weight:600;line-height:1.3;margin-right:8px`">$Name</span> $(New-HuduUiChip -Text $m.Header.EnabledLabel -Tone $m.Header.EnabledTone -Title $m.Header.EnabledTip -Strong)</div>" +
    "<div style=`"font-size:13px;opacity:.75`">$Sub</div>$Synced" +
    "<div style=`"margin-top:10px;padding-top:12px;border-top:1px solid rgba(128,128,128,.2)`">$($LinkHtml -join ' ')</div></div>"

    # Needs attention
    $Attention = Get-HuduUserAttentionItems -Model $m
    $AttentionHtml = if ($Attention.Count) {
        $Items = @(foreach ($a in $Attention) { "<span style=`"display:inline-block;margin:4px 24px 0 0`">$(ConvertTo-HuduUiRich $a)</span>" }) -join ' '
        "<div style=`"margin-top:12px;padding:10px 14px;border-radius:6px;background:rgba(247,144,9,.12);border:1px solid rgba(247,144,9,.5)`">" +
        "<div style=`"font-size:13px;font-weight:600`">$(Get-HuduUiIcon -Name Warning)Needs attention <span style=`"font-weight:400;opacity:.7;margin-left:6px`">$($Attention.Count)</span></div>" +
        "<div style=`"margin-top:2px;font-size:13px`">$Items</div></div>"
    }

    # Contact, mailbox, OneDrive
    $ContactCard = New-HuduUiCard -Title 'Contact' -Icon 'address-card' -Body ((New-HuduUiRow -Label 'Business phone' -Value $m.Contact.BusinessPhone) +
        (New-HuduUiRow -Label 'Mobile' -Value $m.Contact.Mobile) +
        (New-HuduUiRow -Label 'Office' -Value $m.Contact.Office) +
        "<tr><td colspan=`"2`" style=`"$($TableStyle.RowCell);$($TableStyle.RowSep);padding:7px 0`"><div style=`"opacity:.7;margin-bottom:2px`">User ID</div><code style=`"font-size:11px;word-break:break-all`">$(ConvertTo-HuduUiText $m.Contact.UserId)</code></td></tr>")

    $Gauge = {
        param($S, $What)
        "<tr><td style=`"$($TableStyle.RowLabel);opacity:1;vertical-align:baseline;padding:0 12px 6px 0`"><strong style=`"font-size:20px;font-weight:600`">$(ConvertTo-HuduUiText $S.UsedText)</strong> <span style=`"opacity:.7`">of $(ConvertTo-HuduUiText $S.AllocatedText)</span></td><td style=`"$($TableStyle.RowValue);vertical-align:baseline;padding:0 0 6px;opacity:.7`">$(ConvertTo-HuduUiText $S.PctText)</td></tr>" +
        "<tr><td colspan=`"2`" style=`"$($TableStyle.RowCell);padding:0 0 10px`">$(New-HuduUiBar -Pct $S.Pct -Tone $S.Tone -Title "$What usage $($S.PctText)")</td></tr>"
    }
    $MailboxCard = if ($m.Mailbox.Present) {
        New-HuduUiCard -Title 'Mailbox' -Icon 'envelope' -Body ((& $Gauge $m.Mailbox 'Mailbox') +
            (New-HuduUiRow -Label 'Items' -Value $m.Mailbox.Items) +
            (New-HuduUiRow -Label 'Send blocked at' -Value $m.Mailbox.SendBlockedAt) +
            (New-HuduUiRow -Label 'Send and receive blocked at' -Value $m.Mailbox.SendReceiveBlockedAt))
    }
    $OneDriveCard = if ($m.OneDrive.Present) {
        $Flag = if ($m.OneDrive.HasFlag) { New-HuduUiChip -Text $m.OneDrive.FlagText -Tone $m.OneDrive.Tone -Title $m.OneDrive.FlagTip -Strong }
        $Deleted = if ($m.OneDrive.IsDeleted) { New-HuduUiRow -Label 'Deleted' -Value 'Yes' }
        New-HuduUiCard -Title 'OneDrive' -Icon 'cloud' -Flag $Flag -Body ((& $Gauge $m.OneDrive 'OneDrive') +
            (New-HuduUiRow -Label 'Files' -Value $m.OneDrive.Files -Note "$($m.OneDrive.ActiveFiles) active") +
            (New-HuduUiRow -Label 'Last activity' -Value $m.OneDrive.LastActivity) +
            (New-HuduUiRow -Label 'Site URL' -Value $m.OneDrive.SiteUrl) + $Deleted)
    }
    $RowOne = & $Columns @($ContactCard, $MailboxCard, $OneDriveCard) 280

    # Mailbox access and settings
    $AccessCard = if ($m.MailAccess.Count) {
        $Rows = @(foreach ($i in $m.MailAccess) {
                $Owner = if ($i.IsOwner) { ' <span style="opacity:.6">(owner)</span>' }
                $Rights = @(foreach ($r in $i.Rights) { New-HuduUiChip -Text $r -Strong }) -join ' '
                "<tr><td style=`"$Td;padding-left:0;word-break:normal`">$(ConvertTo-HuduUiText $i.Who)$Owner</td><td style=`"$Td;padding-right:0`">$Rights</td></tr>"
            }) -join ''
        New-HuduUiCard -Title 'Mailbox access' -Icon 'user-lock' -Body "<table style=`"$Table`"><tbody><tr><th style=`"$Th;padding-left:0`">Delegate</th><th style=`"$Th;padding-right:0`">Rights</th></tr>$Rows</tbody></table>"
    }
    $SettingsCard = if ($m.MailSettings.Present) {
        $Pro = @(foreach ($p in $m.MailSettings.Protocols) { New-HuduUiChip -Text $p.Name -Tone $(if ($p.On) { 'ok' } else { 'neutral' }) -Strong -Suffix $(if ($p.On) { 'On' } else { 'Off' }) }) -join ' '
        New-HuduUiCard -Title 'Mailbox settings' -Icon 'sliders-h' -Body ("<div style=`"font-size:12px;opacity:.7;margin-bottom:4px`">Protocols</div><div style=`"margin-bottom:10px`">$Pro</div>" +
            (New-HuduUiRow -Label 'Forwarding' -Value $m.MailSettings.Forwarding.Text -Note $m.MailSettings.Forwarding.Note) +
            (New-HuduUiRow -Label 'Litigation hold' -Value $m.MailSettings.LitigationHold) +
            (New-HuduUiRow -Label 'Hidden from address lists' -Value $m.MailSettings.Hidden))
    }
    $RowTwo = if ($AccessCard -or $SettingsCard) { & $Columns @($AccessCard, $SettingsCard) 400 }

    # Licenses and aliases
    $LicCard = if ($m.Licenses.Count -or $m.Aliases.Present) {
        $LicBody = "<div>$(& $Chips $m.Licenses)</div>"
        $AliasHtml = if ($m.Aliases.Present) {
            $X500 = if ($m.Aliases.X500.Count) {
                '<div style="margin-top:10px;font-size:12px;opacity:.75">Legacy X500</div>' +
                (@(foreach ($x in $m.Aliases.X500) { "<div style=`"margin-top:4px`"><code style=`"font-size:11px;word-break:break-all`">$(ConvertTo-HuduUiText $x)</code></div>" }) -join '')
            }
            New-HuduUiSection -Title 'Aliases' -Count $m.Aliases.Summary -Style 'margin-top:12px;border-top:1px solid rgba(128,128,128,.2);padding-top:10px' -Body "<div style=`"margin-top:8px`">$(& $Chips $m.Aliases.Addresses)</div>$X500"
        }
        New-HuduUiCard -Title 'Licenses' -Icon 'key' -Count $m.Licenses.Count -Body "$LicBody$AliasHtml" -Spaced
    }

    # Conditional Access
    $CaCard = if ($m.CA.Items.Count) {
        $Rows = @(foreach ($i in $m.CA.Items) {
                $Cond = if ($i.ConditionsText) { ConvertTo-HuduUiText $i.ConditionsText } else { '<span style="opacity:.55">&ndash;</span>' }
                "<tr><td style=`"$Td;padding-left:0`">$(ConvertTo-HuduUiText $i.Name)</td><td style=`"$Td;white-space:nowrap`">$(New-HuduUiChip -Text $i.StateLabel -Tone $i.StateTone -Strong)</td><td style=`"$Td`">$(ConvertTo-HuduUiText $i.ClientApps)</td><td style=`"$Td;padding-right:0`">$Cond</td></tr>"
            }) -join ''
        $Body = "<table style=`"$Table`"><tbody><tr><th style=`"$Th;padding-left:0`">Policy</th><th style=`"$Th;white-space:nowrap`">State</th><th style=`"$Th`">Client apps</th><th style=`"$Th;padding-right:0`">Conditions and grant</th></tr>$Rows</tbody></table>"
        New-HuduUiCard -Title 'Conditional Access' -Icon 'shield-alt' -Count "$($m.CA.Items.Count) $(if ($m.CA.Items.Count -eq 1) { 'policy' } else { 'policies' })" -Right $m.CA.Summary -Body $Body -Spaced
    }

    # Intune devices
    $DevCard = if ($m.Devices.Items.Count) {
        $Rows = @(foreach ($i in $m.Devices.Items) {
                $Stale = if ($i.IsStale) { New-HuduUiChip -Text $i.StaleText -Tone warn -Title $i.StaleTip -Strong -Small }
                "<tr><td style=`"$Td;padding-left:0`">$(New-HuduUiLink -Url $i.Url -Label $i.Name -Tip $i.Tip -Variant strong)<div style=`"font-size:12px;opacity:.7`">$(ConvertTo-HuduUiText $i.Detail)</div></td>" +
                "<td style=`"$Td`">$(New-HuduUiChip -Text $i.Compliance -Tone $i.Tone -Strong -NoWrap)</td>" +
                "<td style=`"$Td`">$(ConvertTo-HuduUiText $i.Owner)</td>" +
                "<td style=`"$Td`">$(ConvertTo-HuduUiText $i.Os) <code style=`"font-size:11px`">$(ConvertTo-HuduUiText $i.OsVersion)</code></td>" +
                "<td style=`"$Td;white-space:nowrap`">$(ConvertTo-HuduUiText $i.LastSync) $Stale</td>" +
                "<td style=`"$Td;white-space:nowrap;padding-right:0`">$(ConvertTo-HuduUiText $i.Enrolled)</td></tr>"
            }) -join ''
        $Head = "<th style=`"$Th;padding-left:0`">Device</th><th style=`"$Th`">Compliance</th><th style=`"$Th`">Owner</th><th style=`"$Th`">OS</th><th style=`"$Th`">Last sync</th><th style=`"$Th;padding-right:0`">Enrolled</th>"
        New-HuduUiCard -Title 'Intune devices' -Icon 'laptop' -Count $m.Devices.Items.Count -Right $m.Devices.Summary -Body "<table style=`"$Table`"><tbody><tr>$Head</tr>$Rows</tbody></table>" -Spaced
    }

    # Groups
    $GroupCard = if ($m.Groups.Total) {
        $Segments = @(for ($n = 0; $n -lt $m.Groups.Categories.Count; $n++) {
                $c = $m.Groups.Categories[$n]
                $Left = if ($n) { 'margin-left:2px;' } else { '' }
                "<div title=`"$(ConvertTo-HuduUiText "$($c.Title): $($c.Count)")`" style=`"display:inline-block;vertical-align:top;height:8px;$($Left)width:$($c.Pct)%;background:$($c.Color)`"></div>"
            }) -join ''
        $Sections = @(foreach ($c in $m.Groups.Categories) {
                $GroupChips = @(foreach ($g in $c.Items) { New-HuduUiChip -Text $g.Name -Suffix $g.CountLabel }) -join ' '
                New-HuduUiSection -Title $c.Title -Count $c.Count -Body "<div style=`"margin-top:8px`">$GroupChips</div>"
            }) -join ''
        $Body = "<div style=`"height:8px;white-space:nowrap;font-size:0;line-height:0;border-radius:4px;overflow:hidden;background:rgba(128,128,128,.22);margin-bottom:6px`" title=`"$(ConvertTo-HuduUiText "Groups by type: $($m.Groups.Summary)")`">$Segments</div>$Sections"
        New-HuduUiCard -Title 'Groups' -Icon 'users' -Count $m.Groups.Total -Right $m.Groups.Summary -Body $Body -Spaced -HeadingGap 10
    }

    # Service plans
    $PlanCard = if ($m.Plans.Items.Count) {
        $PlanChips = @(foreach ($i in $m.Plans.Items) { New-HuduUiChip -Text $i.Name -Title $i.Title -Suffix $i.CountLabel }) -join ' '
        New-HuduUiCard -Title 'Service plans' -Icon 'cubes' -Count $m.Plans.Items.Count -Right "$($m.Plans.AssignmentCount) assignments, shown once with the most recent date on hover" -Body "<div>$PlanChips</div>" -Spaced -HeadingGap 10
    }

    "<div style=`"overflow:hidden`">$HeaderCard$AttentionHtml$RowOne$RowTwo$LicCard$CaCard$DevCard$GroupCard$PlanCard</div>"
}
