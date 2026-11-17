function Invoke-CIPPOffboardingOneDriveCopy {
    <#
    .SYNOPSIS
        Offboarding step: starts a copy of the leaver's OneDrive into each recipient's OneDrive and/or a document library.
    .DESCRIPTION
        Accepts the wizard's {label,value} recipients and returns one line of text for the offboarding results.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        # The leaver's UPN.
        [Parameter(Mandatory = $true)]
        [string]$Username,

        # UPNs or object ids, as strings or {label, value} objects.
        $Recipients,

        # {site, library, folder} as the wizard's library picker sends it.
        $Library,

        # Chosen by Invoke-CIPPOffboardingJob and also given to the licence step, which waits for this copy.
        [string]$OperationId,

        $APIName = 'Offboard user',
        $Headers
    )

    $RecipientIds = @(foreach ($Recipient in @($Recipients)) {
            if ($null -eq $Recipient) { continue }
            $Value = if ($Recipient -is [System.Collections.IDictionary]) { $Recipient['value'] } else { $Recipient.value ?? $Recipient }
            if ($Value -is [string] -and -not [string]::IsNullOrWhiteSpace($Value)) { $Value.Trim() }
        })
    $HasLibrary = -not [string]::IsNullOrWhiteSpace([string]($Library.library.value ?? $Library.library))
    if ($RecipientIds.Count -eq 0 -and -not $HasLibrary) {
        throw 'No OneDrive copy recipients or document library were given.'
    }

    $StartParams = @{
        TenantFilter = $TenantFilter
        Leaver       = $Username
        Recipients   = $RecipientIds
        Library      = if ($HasLibrary) { $Library }
        Headers      = $Headers
        APIName      = $APIName
        # Disable sign in ran a step earlier; give Graph a moment to show the account as blocked.
        WaitForSignInBlock = $true
    }
    if ($OperationId) { $StartParams.OperationId = $OperationId }
    $Result = Start-CIPPOneDriveCopyToUser @StartParams

    $Started = @($Result.Recipients | Where-Object { $_.State -ne 'Failed' } | ForEach-Object { $_.UserPrincipalName })
    $Failed = @($Result.Recipients | Where-Object { $_.State -eq 'Failed' } | ForEach-Object { "$($_.UserPrincipalName) ($($_.Message))" })
    $Text = "Started OneDrive copy $($Result.OperationId) of $Username into folder $($Result.FolderName) for $($Started -join ', ') ($($Result.RootItemCount) root items, $($Result.ExpectedBytes) bytes)."
    if ($Failed.Count -gt 0) {
        $Text = "Error: OneDrive copy $($Result.OperationId) did not start for $($Failed -join ', '). $Text"
    }
    if (@($Result.Warnings).Count -gt 0) {
        $Text = "$Text Warnings: $(@($Result.Warnings) -join ' ')"
    }
    return $Text
}
