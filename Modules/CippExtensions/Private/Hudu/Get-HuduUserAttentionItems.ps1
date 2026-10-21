function Get-HuduUserAttentionItems {
    <#
        .SYNOPSIS
        Lists what needs a human on a user, from a Get-HuduUserViewModel model.

        .DESCRIPTION
        Returns plain sentences; **text** marks emphasis. Storage tones and device
        staleness use the thresholds the model was built with.
    #>
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Model)

    $m = $Model
    $Items = [System.Collections.Generic.List[string]]::new()
    $Plural = { param([int]$n, $One, $Many) if ($n -eq 1) { $One } else { $Many } }

    if (-not $m.Header.IsEnabled) { $Items.Add('**Account is disabled**') }
    foreach ($Store in @(@{ Name = 'OneDrive'; Data = $m.OneDrive }, @{ Name = 'Mailbox'; Data = $m.Mailbox })) {
        $S = $Store.Data
        if ($S.Present -and $S.Tone -ne 'ok') { $Items.Add("$($Store.Name) is **$($S.PctText)** full ($($S.UsedText.Replace(' GB', '')) of $($S.AllocatedText))") }
    }
    $NonComp = @($m.Devices.Items | Where-Object { $_.IsNonCompliant })
    if ($NonComp.Count) {
        $Items.Add("**$($NonComp.Count) $(& $Plural $NonComp.Count 'device' 'devices')** $(& $Plural $NonComp.Count 'is' 'are') non-compliant: $($NonComp.Name -join ', ')")
    }
    $Stale = @($m.Devices.Items | Where-Object { $_.IsStale })
    if ($Stale.Count) {
        $Items.Add("**$($Stale.Count) $(& $Plural $Stale.Count 'device' 'devices')** not synced in over $($m.Devices.StaleAfterDays) days: $($Stale.Name -join ', ')")
    }
    $Ro = [int]$m.CA.ReportOnlyCount
    if ($Ro) { $Items.Add("**$Ro Conditional Access $(& $Plural $Ro 'policy' 'policies')** $(& $Plural $Ro 'is' 'are') report-only") }
    if ($m.MailSettings.Present -and $m.MailSettings.Forwarding.IsActive) { $Items.Add("Mail is forwarded to **$($m.MailSettings.Forwarding.Text)**") }

    , $Items
}
