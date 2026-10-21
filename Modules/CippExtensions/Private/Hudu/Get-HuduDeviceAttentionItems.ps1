function Get-HuduDeviceAttentionItems {
    <#
        .SYNOPSIS
        Lists what needs a human on a device, from a Get-HuduDeviceViewModel model.

        .DESCRIPTION
        Returns plain sentences; **text** marks emphasis. Storage tone and staleness use the thresholds the model was
        built with.
    #>
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Model)

    $m = $Model
    $Items = [System.Collections.Generic.List[string]]::new()
    if ($m.Header.IsNonCompliant) { $Items.Add('Device is **non-compliant**') }
    if ($m.Header.IsStale) { $Items.Add("**Not synced in over $($m.Header.StaleAfterDays) days**") }
    $S = $m.Hardware.Storage
    if ($S.Present -and $S.Tone -ne 'ok') { $Items.Add("Storage is **$($S.PctText)** full ($($S.UsedText.Replace(' GB', '')) of $($S.AllocatedText))") }
    , $Items
}
