function Invoke-CIPPOffboardingOneDriveCopy {
    <#
    .SYNOPSIS
        Offboarding step: starts a copy of the leaver's OneDrive into each recipient's OneDrive.
    .DESCRIPTION
        Thin wrapper over Start-CIPPOneDriveCopyToUser (the same core the ExecOneDriveCopyToUser
        endpoint uses) that accepts the wizard's {label,value} recipients and returns one line of text
        for the offboarding results. It only starts the copy; when the offboarding also removes licences,
        Remove-CIPPLicenseAfterOneDriveCopy waits for it to complete.
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
    if ($RecipientIds.Count -eq 0) {
        throw 'No OneDrive copy recipients were given.'
    }

    $Principal = try {
        [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json
    } catch { $null }
    $StartedBy = $Principal.userDetails ?? $Headers.'x-ms-client-principal-name' ?? 'CIPP offboarding'

    $StartParams = @{
        TenantFilter = $TenantFilter
        Leaver       = $Username
        Recipients   = $RecipientIds
        StartedBy    = $StartedBy
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
