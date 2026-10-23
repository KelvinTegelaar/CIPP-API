function Invoke-CIPPBecRelease {
    <#
    .SYNOPSIS
        Lifts the lockouts a BEC case's containment placed on the user.
    .DESCRIPTION
        Reads the containment history recorded on the case and reverses the actions the catalog marks
        Release = 'Reverse' that succeeded since the last release: re-enables sign-in, restores the
        mailbox protocol settings, unblocks the mobile devices containment blocked, re-enables the
        registered devices it disabled and removes the targeted Conditional Access policy. Protocol
        settings and the device block list come from the state the containment recorded before it
        changed them, else from the investigation's mailbox snapshot, so a protocol or device that was
        already off stays off. Attacker cleanup (Release = 'Keep') is left in place and actions that
        cannot be undone (Release = 'Manual') are listed for the operator; both come back as info rows.
        The release is appended to the case history with Kind = 'Release'.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER CaseId
        The BEC case whose containment is released.
    .PARAMETER Actions
        Reversible action ids to release. Empty = every reversible action the containment ran.
    .PARAMETER Headers
        CIPP request headers for logging.
    .PARAMETER APIName
        Logging API name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$CaseId,
        [string[]]$Actions = @(),
        $Headers,
        [string]$APIName = 'BECRelease'
    )

    $Run = Get-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId -IncludeResults
    if (-not $Run) { throw "BEC case $CaseId was not found" }
    $Upn = [string]$Run.UserPrincipalName
    $UserId = [string]$Run.UserId
    $Snapshot = $Run.Results.MailboxState

    # Only containment after the most recent release is still in force
    $History = @($Run.Containment | Where-Object { $_ })
    $LastRelease = -1
    for ($i = 0; $i -lt $History.Count; $i++) { if ($History[$i].Kind -eq 'Release') { $LastRelease = $i } }
    $Entries = @($History | Select-Object -Skip ($LastRelease + 1) | Where-Object { $_.Kind -ne 'Release' })
    $Succeeded = @($Entries | ForEach-Object { $_.Results } | Where-Object { $_ -and $_.state -in @('success', 'warning') })
    $Ran = @($Succeeded.Action | Select-Object -Unique)

    $Catalog = Get-CIPPBecContainmentActions
    $Reversible = @($Catalog | Where-Object { $_.Release -eq 'Reverse' -and $_.Id -in $Ran } | Sort-Object -Property Order)
    if ($Actions.Count -gt 0) {
        $NotReleasable = @($Actions | Where-Object { $_ -notin $Reversible.Id })
        if ($NotReleasable.Count -gt 0) { throw "Not releasable on this case: $($NotReleasable -join ', ')" }
        $Reversible = @($Reversible | Where-Object { $_.Id -in $Actions })
    }
    if ($Reversible.Count -eq 0) { throw "Case $CaseId has no containment in force to release" }

    # The earliest recording saw the mailbox before any containment touched it
    $FirstBefore = {
        param($Id)
        foreach ($Entry in $Entries) { if ($Entry.Before -and $Entry.Before.$Id) { return $Entry.Before.$Id } }
    }

    $Rows = [System.Collections.Generic.List[object]]::new()
    $Add = { param($Action, $Target, $State, $Text) $Rows.Add([pscustomobject]@{ Action = $Action; Target = $Target; state = $State; resultText = $Text }) }

    foreach ($Action in $Reversible) {
        $Id = $Action.Id
        try {
            switch ($Id) {
                'DisableAccount' {
                    try {
                        & $Add $Id $Upn 'success' ([string](Set-CIPPSignInState -UserID $Upn -AccountEnabled $true -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers))
                    } catch {
                        if ($_.Exception.Message -match 'AD Sync enabled') {
                            & $Add $Id $Upn 'warning' "Sign-in re-enabled in Entra ID for $Upn, but the account is directory-synced: enable it on-premises too or the next sync blocks it again."
                        } else { throw }
                    }
                }
                'BlockProtocols' {
                    $Prior = & $FirstBefore $Id
                    $Settings = @{}
                    if ($Prior) {
                        foreach ($Property in $Prior.PSObject.Properties) { $Settings[$Property.Name] = $Property.Value }
                    } elseif ($Snapshot) {
                        foreach ($Name in @('EWSEnabled', 'IMAPEnabled', 'POPEnabled', 'ActiveSyncEnabled', 'OWAEnabled', 'MAPIEnabled', 'ECPEnabled', 'SmtpClientAuthenticationDisabled')) {
                            if ($Snapshot.PSObject.Properties[$Name]) { $Settings[$Name] = $Snapshot.$Name }
                        }
                    }
                    if ($Settings.Count -eq 0) {
                        & $Add $Id $Upn 'warning' 'The protocol settings before containment were not recorded; re-enable the protocols on the mailbox manually.'
                        break
                    }
                    $CasParams = @{ Identity = $Upn }
                    foreach ($Name in $Settings.Keys) { $CasParams[$Name] = $Settings[$Name] }
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-CASMailbox' -cmdParams $CasParams -Anchor $Upn
                    $Summary = @($Settings.Keys | Sort-Object | ForEach-Object { "$_=$(if ($null -eq $Settings[$_]) { 'default' } else { $Settings[$_] })" }) -join ', '
                    & $Add $Id $Upn 'success' "Restored mailbox protocol settings for $Upn ($Summary)"
                }
                'BlockMobileDevices' {
                    $Prior = & $FirstBefore $Id
                    $AlreadyBlocked = if ($Prior) { @($Prior.ActiveSyncBlockedDeviceIDs) } elseif ($Snapshot) { @($Snapshot.ActiveSyncBlockedDeviceIDs) } else { @() }
                    $Blocked = @($Succeeded | Where-Object { $_.Action -eq $Id } | ForEach-Object { [string]$_.Target } | Where-Object { $_ } | Select-Object -Unique)
                    $Unblock = @($Blocked | Where-Object { $_ -notin $AlreadyBlocked })
                    foreach ($DeviceId in @($Blocked | Where-Object { $_ -in $AlreadyBlocked })) {
                        & $Add $Id $DeviceId 'info' "Left $DeviceId blocked: it was on the block list before containment"
                    }
                    if ($Unblock.Count -eq 0) { break }
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-CASMailbox' -cmdParams @{ Identity = $Upn; ActiveSyncBlockedDeviceIDs = @{ '@odata.type' = '#Exchange.GenericHashTable'; remove = $Unblock } } -Anchor $Upn
                    foreach ($DeviceId in $Unblock) { & $Add $Id $DeviceId 'success' "Removed $DeviceId from the mobile device block list for $Upn" }
                }
                'DisableRegisteredDevices' {
                    foreach ($DeviceId in @($Succeeded | Where-Object { $_.Action -eq $Id } | ForEach-Object { [string]$_.Target } | Where-Object { $_ } | Select-Object -Unique)) {
                        try {
                            & $Add $Id $DeviceId 'success' ([string](Set-CIPPDeviceState -Action Enable -DeviceID $DeviceId -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName))
                        } catch { & $Add $Id $DeviceId 'error' $_.Exception.Message }
                    }
                }
                'TargetedCAPolicy' {
                    if (-not $UserId) { throw "The case has no user object id to find the targeted Conditional Access policy by" }
                    & $Add $Id $Upn 'success' ([string](Remove-CIPPBecTargetedCAPolicy -TenantFilter $TenantFilter -UserId $UserId -Headers $Headers -APIName $APIName))
                }
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            & $Add $Id $Upn 'error' "Releasing '$($Action.Label)' failed: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "BEC release action $Id failed for $Upn`: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        }
    }

    foreach ($Action in @($Catalog | Where-Object { $_.Id -in $Ran -and $_.Release -in @('Keep', 'Manual') } | Sort-Object -Property Order)) {
        $Text = if ($Action.Release -eq 'Keep') { "Left in place: '$($Action.Label)' removed attacker changes" } else { "Not reversed: '$($Action.Label)' cannot be undone automatically; review it manually" }
        & $Add $Action.Id $Upn 'info' $Text
    }

    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Released BEC containment for $Upn ($($Reversible.Id -join ', ')) [case $CaseId]" -Sev 'Info' -LogData @($Rows)
    try {
        $By = if ($Headers -and $Headers.'x-ms-client-principal') { try { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } catch { 'CIPP' } } elseif ($Headers -is [string]) { $Headers } else { 'CIPP' }
        $Updated = [System.Collections.Generic.List[object]]::new()
        foreach ($Entry in $History) { $Updated.Add($Entry) }
        $Updated.Add([pscustomobject]@{ Kind = 'Release'; At = (Get-Date).ToUniversalTime().ToString('o'); By = [string]$By; Actions = @($Reversible.Id); Results = @($Rows) })
        $null = Set-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId -Properties @{ Containment = @($Updated) }
    } catch {
        Write-Information "BEC release: could not record the release on case $CaseId`: $($_.Exception.Message)"
    }
    return $Rows.ToArray()
}
