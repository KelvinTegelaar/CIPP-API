function New-CippExtensionUiSynced {
    <#
        .SYNOPSIS
        The "Synced" block line for a header: local time in the given zone with its UTC offset, and the UTC time on hover.
    #>
    param(
        [Parameter(Mandatory)][datetime]$SyncedAt,
        [cultureinfo]$Culture = [cultureinfo]::GetCultureInfo('en-GB'),
        [TimeZoneInfo]$TimeZone = [TimeZoneInfo]::Utc
    )
    $Utc = $SyncedAt.ToUniversalTime()
    $Local = [TimeZoneInfo]::ConvertTimeFromUtc($Utc, $TimeZone)
    $Offset = $TimeZone.GetUtcOffset($Utc)
    $Zone = if ($Offset -eq [TimeSpan]::Zero) { 'UTC' } else { '(UTC{0}{1:hh\:mm})' -f $(if ($Offset -lt [TimeSpan]::Zero) { '-' } else { '+' }), $Offset.Duration() }
    $Text = "Synced $($Local.ToString("$(Get-CippExtensionUiDatePattern $Culture) HH:mm", $Culture)) $Zone"
    "<div style=`"font-size:12px;opacity:.7;margin-top:4px`" title=`"Last Updated: $($Utc.ToString('yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture)) UTC`">$(ConvertTo-CippExtensionUiText $Text)</div>"
}
