function Get-CIPPBaselineGlobalSecureAccessInternetAccessState {
    <#
    .SYNOPSIS
        Prepare hook for the Internet Access standard: the Internet traffic profile plus the custom block page.
    .DESCRIPTION
        The Internet traffic profile is graded by the shared traffic profile hook. The custom block page
        is graded from the NetworkAccess cache only for what is configured: its state when set, its
        message when not blank. A needed write is carried for GraphBulkSweep as blockPageWrites (state and
        message) or blockPageStateWrites (state only). Graph requires a message to enable the page and
        refuses an empty one, so enabling without a configured message reuses the tenant's current
        message; disabling without one writes the state alone, which keeps the current message.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter)

    $State = Get-CIPPBaselineGlobalSecureAccessTrafficProfileState -Item $Item -TenantFilter $TenantFilter
    if ($null -eq $State.Current) { return $State }

    $BlockPageState = "$($Item.Variables.blockPageState.value ?? $Item.Variables.blockPageState)"
    $Message = "$($Item.Variables.blockMessage)"
    $BlockPageWrites = @()
    $BlockPageStateWrites = @()
    if ($BlockPageState -or $Message) {
        $Cached = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'NetworkAccess').Where({ $_ }, 'First')[0].customBlockPage
        $Drift = $false
        if ($BlockPageState) {
            $State.Expected | Add-Member -NotePropertyName 'blockPageState' -NotePropertyValue $BlockPageState
            $State.Current | Add-Member -NotePropertyName 'blockPageState' -NotePropertyValue "$($Cached.state)"
            $Drift = $BlockPageState -ne "$($Cached.state)"
        }
        if ($Message) {
            $State.Expected | Add-Member -NotePropertyName 'blockPageMessage' -NotePropertyValue $Message
            $State.Current | Add-Member -NotePropertyName 'blockPageMessage' -NotePropertyValue "$($Cached.message)"
            $Drift = $Drift -or $Message -cne "$($Cached.message)"
        }
        $WriteState = $BlockPageState ? $BlockPageState : ("$($Cached.state)" ? "$($Cached.state)" : 'enabled')
        $WriteMessage = $Message ? $Message : "$($Cached.message)"
        if ($Drift -and ($Message -or $WriteState -eq 'enabled')) {
            if ([string]::IsNullOrWhiteSpace($WriteMessage)) {
                return @{ Current = $null; ConfigError = $true; NoDataReason = 'enabling the custom block page needs a message, and the tenant has none yet; add a block page message' }
            }
            $BlockPageWrites = @([pscustomobject]@{ state = $WriteState; message = $WriteMessage })
        } elseif ($Drift) {
            $BlockPageStateWrites = @([pscustomobject]@{ state = $WriteState })
        }
    }
    $State.Current | Add-Member -NotePropertyName 'blockPageWrites' -NotePropertyValue $BlockPageWrites
    $State.Current | Add-Member -NotePropertyName 'blockPageStateWrites' -NotePropertyValue $BlockPageStateWrites
    $State
}
