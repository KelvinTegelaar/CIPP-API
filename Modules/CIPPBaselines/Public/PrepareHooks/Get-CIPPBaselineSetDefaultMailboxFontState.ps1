function Get-CIPPBaselineSetDefaultMailboxFontState {
    <#
    .SYNOPSIS
        Prepare hook for SetDefaultMailboxFont: user and shared mailboxes whose default compose
        font differs from the configured name, size or colour.
    .DESCRIPTION
        Grades the MailboxMessageConfiguration cache, one row per mailbox. A row whose read
        failed is graded as drift under 'unreadable'; when no row could be read at all the
        result is No Data, never Compliant.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter)

    $FontName = "$($Item.Variables.DefaultFontName)"
    $FontColor = "$($Item.Variables.DefaultFontColor)"
    $FontSize = 0
    if ([string]::IsNullOrWhiteSpace($FontName) -or [string]::IsNullOrWhiteSpace($FontColor)) {
        return @{ Current = $null; NoDataReason = 'font name and colour must both be set'; ConfigError = $true }
    }
    # 1-7 is the legacy scale Exchange documents (3 = 12pt), but Exchange also stores 8-72 and OWA renders those as point sizes (issue #881)
    if (-not [int]::TryParse("$($Item.Variables.DefaultFontSize)", [ref]$FontSize) -or $FontSize -lt 1 -or $FontSize -gt 72) {
        return @{ Current = $null; NoDataReason = "'$($Item.Variables.DefaultFontSize)' is not a valid font size. Exchange accepts an integer between 1 and 72 (1-7 is the legacy scale, 8-72 is a point size)"; ConfigError = $true }
    }
    # Exchange stores #xxxxxx; shorthand would never match the read-back and rewrite every mailbox each run
    if ($FontColor -notmatch '^#[0-9A-Fa-f]{6}$') {
        return @{ Current = $null; NoDataReason = "'$FontColor' is not a valid hex colour. Exchange expects the #xxxxxx format"; ConfigError = $true }
    }

    $Configs = @((New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'MailboxMessageConfiguration').Where({ $_.id }))
    if ($Configs.Count -eq 0) { return @{ Current = $null } }

    $Offending = [System.Collections.Generic.List[string]]::new()
    $Unreadable = [System.Collections.Generic.List[string]]::new()
    foreach ($Config in $Configs) {
        # A missing size would coerce to 0 and drift forever, so it counts as a failed read
        if ($Config.error -or $null -eq $Config.DefaultFontSize) {
            $Unreadable.Add("$($Config.id)")
            continue
        }
        if ($Config.DefaultFontName -ne $FontName -or [int]$Config.DefaultFontSize -ne $FontSize -or $Config.DefaultFontColor -ne $FontColor) {
            $Offending.Add("$($Config.id)")
        }
    }
    if ($Unreadable.Count -eq $Configs.Count) {
        return @{ Current = $null; NoDataReason = "no mailbox message configuration could be read ($($Unreadable.Count) of $($Configs.Count) mailboxes failed)" }
    }

    @{
        Current = [PSCustomObject]@{
            offenders  = @($Offending | Sort-Object)
            unreadable = @($Unreadable | Sort-Object)
            targets    = @(foreach ($UPN in $Offending) { [PSCustomObject]@{ id = $UPN } })
        }
    }
}
