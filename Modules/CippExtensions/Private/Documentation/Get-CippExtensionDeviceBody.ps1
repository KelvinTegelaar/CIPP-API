function Get-CippExtensionDeviceBody {
    <#
        .SYNOPSIS
        Renders the Microsoft 365 rich-text field of a documentation device record from a Get-CippExtensionDeviceViewModel model.

        .DESCRIPTION
        Inline styles only, no fixed text colours, so one output reads in Hudu light and dark. Every model value
        is encoded by the building blocks. Sections without data are left out.

        .PARAMETER SyncedAt
        Shown in the header when given.

        .PARAMETER Layout
        NinjaOne strips CSS grid, backgrounds, opacity and border-top and paints its own cell grid, so its card row uses
        its Bootstrap grid classes, cells are padded on every side, chips and accents use borders and text colour.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Model,
        [Nullable[datetime]]$SyncedAt,
        [cultureinfo]$Culture = [cultureinfo]::GetCultureInfo('en-GB'),
        [TimeZoneInfo]$TimeZone = [TimeZoneInfo]::Utc,
        [ValidateSet('Hudu', 'NinjaOne')][string]$Layout = 'Hudu'
    )

    $m = $Model
    # Hudu strips the CSS gap property and its mobile app ignores flex and margins on inline-blocks,
    # so rows are inline flow with margins plus a literal space between inline-block items
    $TableStyle = Get-CippExtensionUiTableStyle
    $Th = $TableStyle.Th
    $Td = $TableStyle.Td
    $Table = $TableStyle.Table
    $Sep = '<span style="display:inline-block;vertical-align:middle;width:1px;height:20px;background:rgba(128,128,128,.4);margin:0 8px 6px 2px"></span>'
    $LinkLabel = { param($t) "<span style=`"display:inline-block;vertical-align:middle;font-size:12px;opacity:.7;margin:0 8px 6px 0`">$t</span>" }
    # Hudu's mobile app ignores grid and stacks the cells, which suits a phone
    $Columns = {
        param($Cards, $Basis)
        if ($Layout -eq 'NinjaOne') {
            $Cells = @(foreach ($c in $Cards) { if ($c) { "<div class=`"col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex`">$($c -replace '^<div ', '<div class="flex-grow-1" ')</div>" } }) -join ''
            return "<div class=`"row g-3`" style=`"margin-top:0`">$Cells</div>"
        }
        $Cells = @(foreach ($c in $Cards) { if ($c) { "<div style=`"min-width:0;margin:6px`">$c</div>" } }) -join ''
        "<div style=`"display:grid;grid-template-columns:repeat(auto-fit,minmax($($Basis)px,1fr));margin:6px -6px -6px`">$Cells</div>"
    }
    $Muted = '<span style="opacity:.55">&ndash;</span>'
    $h = $m.Header

    # Header card
    $LinkHtml = [System.Collections.Generic.List[string]]::new()
    $LinkHtml.Add((& $LinkLabel 'Microsoft'))
    foreach ($i in $m.Links.Microsoft) { $LinkHtml.Add((New-CippExtensionUiLink -Url $i.Url -Label $i.Label -Tip $i.Tip -Variant button)) }
    if ($m.Links.Rmm.Count) {
        $LinkHtml.Add($Sep); $LinkHtml.Add((& $LinkLabel 'RMM'))
        foreach ($i in $m.Links.Rmm) { $LinkHtml.Add((New-CippExtensionUiLink -Url $i.Url -Label $i.Label -Tip $i.Tip -Variant button)) }
    }
    $Os = (@($h.Os, $h.OsVersion) | Where-Object { $_ } | ForEach-Object { ConvertTo-CippExtensionUiText $_ }) -join ' '
    $User = if ($h.UserName -and $h.UserPrincipal) { "$(ConvertTo-CippExtensionUiText $h.UserName) ($(ConvertTo-CippExtensionUiText $h.UserPrincipal))" } else { ConvertTo-CippExtensionUiText "$($h.UserName)$($h.UserPrincipal)" }
    $Sub = (@($Os, $User) | Where-Object { $_ }) -join ' &middot; '
    $Synced = if ($SyncedAt) { New-CippExtensionUiSynced -SyncedAt $SyncedAt -Culture $Culture -TimeZone $TimeZone }
    $HeaderCard = "<div style=`"border:1px solid rgba(128,128,128,.3);border-top:3px solid #f77f00;border-radius:6px;padding:14px 16px 8px;box-sizing:border-box`">" +
    "<div><span style=`"vertical-align:middle;font-size:18px;font-weight:600;line-height:1.3;margin-right:8px`">$(ConvertTo-CippExtensionUiText $h.Name)</span> $(New-CippExtensionUiChip -Text $h.Compliance -Tone $h.ComplianceTone -Strong)</div>" +
    "<div style=`"font-size:13px;opacity:.75`">$Sub</div>$Synced" +
    "<div style=`"margin-top:10px;padding-top:12px;border-top:1px solid rgba(128,128,128,.2)`">$($LinkHtml -join ' ')</div></div>"

    # Needs attention
    $Attention = Get-CippExtensionDeviceAttentionItems -Model $m
    $AttentionHtml = if ($Attention.Count) {
        $Items = @(foreach ($a in $Attention) { "<span style=`"display:inline-block;margin:4px 24px 0 0`">$(ConvertTo-CippExtensionUiRich $a)</span>" }) -join ' '
        "<div style=`"margin-top:12px;padding:10px 14px;border-radius:6px;background:rgba(247,144,9,.12);border:1px solid rgba(247,144,9,.5)`">" +
        "<div style=`"font-size:13px;font-weight:600`">$(Get-CippExtensionUiIcon -Name Warning)Needs attention <span style=`"font-weight:400;opacity:.7;margin-left:6px`">$($Attention.Count)</span></div>" +
        "<div style=`"margin-top:2px;font-size:13px`">$Items</div></div>"
    }

    # Device details, hardware, enrollment and security
    $DetailsCard = New-CippExtensionUiCard -Title 'Device details' -Icon 'laptop' -Body ((New-CippExtensionUiRow -Label 'Owner' -Value $m.Details.Owner) +
        (New-CippExtensionUiRow -Label 'Enrolled' -Value $m.Details.Enrolled) +
        (New-CippExtensionUiRow -Label 'Last check-in' -Value $m.Details.LastSync) +
        (New-CippExtensionUiRow -Label 'Management agent' -Value $m.Details.ManagementAgent))

    $S = $m.Hardware.Storage
    $StorageHtml = if ($S.Present) {
        "<tr><td style=`"$($TableStyle.RowLabel);$($TableStyle.RowSep)`">Storage</td><td style=`"$($TableStyle.RowValue);$($TableStyle.RowSep)`">$(ConvertTo-CippExtensionUiText $S.UsedText) <span style=`"opacity:.7`">of $(ConvertTo-CippExtensionUiText $S.AllocatedText), $(ConvertTo-CippExtensionUiText $S.FreeText) free, $(ConvertTo-CippExtensionUiText $S.PctText) used</span></td></tr>" +
        $(if ($Layout -eq 'NinjaOne') {
                # NinjaOne strips background fills, so the bar is drawn with borders
                $BarColor = if ($S.Tone -in 'ok', 'neutral') { '#f77f00' } else { (Get-CippExtensionUiTone $S.Tone).Bar }
                "<tr><td colspan=`"2`" style=`"$($TableStyle.RowCell);padding:0 0 7px`"><div style=`"height:8px;border:1px solid rgba(128,128,128,.4);border-radius:4px`"><div style=`"width:$(ConvertTo-CippExtensionUiText $S.Pct)%;height:8px;border:4px solid $BarColor;box-sizing:border-box;border-radius:4px`"></div></div></td></tr>"
            } else { "<tr><td colspan=`"2`" style=`"$($TableStyle.RowCell);padding:0 0 7px`">$(New-CippExtensionUiBar -Pct $S.Pct -Tone $S.Tone -Title "Storage usage $($S.PctText)")</td></tr>" })
    }
    $HardwareCard = New-CippExtensionUiCard -Title 'Hardware' -Icon 'microchip' -Body ((New-CippExtensionUiRow -Label 'Serial number' -Value $m.Hardware.Serial) +
        (New-CippExtensionUiRow -Label 'Chassis' -Value $m.Hardware.Chassis) +
        (New-CippExtensionUiRow -Label 'Model' -Value $m.Hardware.Model) +
        (New-CippExtensionUiRow -Label 'Manufacturer' -Value $m.Hardware.Manufacturer) + $StorageHtml)

    $e = $m.Enrollment
    $EnrollmentCard = New-CippExtensionUiCard -Title 'Enrollment and security' -Icon 'shield-alt' -Body ((New-CippExtensionUiRow -Label 'Enrollment type' -Value $e.EnrollmentType) +
        (New-CippExtensionUiRow -Label 'Join type' -Value $e.JoinType) +
        (New-CippExtensionUiRow -Label 'Registration state' -Value $e.RegistrationState) +
        (New-CippExtensionUiRow -Label 'Autopilot enrolled' -Value $e.Autopilot) +
        (New-CippExtensionUiRow -Label 'Device Guard requirements' -Value $e.DeviceGuard) +
        (New-CippExtensionUiRow -Label 'Virtualization-based security' -Value $e.Vbs) +
        (New-CippExtensionUiRow -Label 'Credential Guard' -Value $e.CredentialGuard))
    $RowOne = & $Columns @($DetailsCard, $HardwareCard, $EnrollmentCard) 320

    # Compliance policies
    $PolicyCard = if ($m.Policies.Count) {
        $Rows = @(foreach ($i in $m.Policies) {
                $Grace = if ($i.GraceExpiry) { ConvertTo-CippExtensionUiText $i.GraceExpiry } else { $Muted }
                $Report = if ($i.LastReport) { ConvertTo-CippExtensionUiText $i.LastReport } else { $Muted }
                "<tr><td style=`"$Td;padding-left:0`">$(ConvertTo-CippExtensionUiText $i.Name)</td><td style=`"$Td;white-space:nowrap`">$(New-CippExtensionUiChip -Text $i.StateLabel -Tone $i.StateTone -Strong)</td><td style=`"$Td;white-space:nowrap`">$Report</td><td style=`"$Td;padding-right:0;white-space:nowrap`">$Grace</td></tr>"
            }) -join ''
        $Head = "<th style=`"$Th;padding-left:0`">Policy</th><th style=`"$Th`">State</th><th style=`"$Th`">Last report</th><th style=`"$Th;padding-right:0`">Grace period ends</th>"
        New-CippExtensionUiCard -Title 'Compliance policies' -Icon 'clipboard-check' -Count $m.Policies.Count -Spaced -Body "<table style=`"$Table`"><tbody><tr>$Head</tr>$Rows</tbody></table>"
    }

    # Groups
    $GroupCard = if ($m.Groups.Count) {
        $Chips = @(foreach ($g in $m.Groups) { New-CippExtensionUiChip -Text $g }) -join ' '
        New-CippExtensionUiCard -Title 'Groups' -Icon 'users' -Count $m.Groups.Count -Spaced -Body "<div>$Chips</div>"
    }

    $Html = "<div style=`"overflow:hidden`">$HeaderCard$AttentionHtml$RowOne$PolicyCard$GroupCard</div>"
    if ($Layout -eq 'NinjaOne') { $Html = ConvertTo-CippExtensionNinjaOneHtml -Html $Html }
    $Html
}
