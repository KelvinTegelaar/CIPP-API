function Invoke-CIPPBecContainment {
    <#
    .SYNOPSIS
        Runs a selectable set of BEC containment actions for one user.
    .DESCRIPTION
        The single containment implementation shared by the ExecBECRemediate endpoint, the
        'becremediate' audit-log alert action and the scheduler. Actions come from
        Get-CIPPBecContainmentActions; with no selection the default set runs (the catalog's
        DefaultSelected flags, which the instance-wide settings can change). Actions run in catalog
        order, each in its own try/catch so one failure never stops the rest, and every action returns
        result rows
        ({ Action, Target, state, resultText, copyField }).

        Targets come from Parameters (explicit ids the operator picked), else from the run's stored
        results (flagged items), else - only when neither exists - from the live tenant.

        Critical actions refuse to run unless -Confirmed is set; the endpoint sets it only after the
        operator typed the user's UPN, automation sets it by design. Passwords never reach the log or
        the stored containment history: the redacted copy of the rows is what gets persisted.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserId
        The user's object id (resolved from the UPN when omitted and needed).
    .PARAMETER UserPrincipalName
        The user's UPN.
    .PARAMETER Actions
        Action ids to run. Empty = the default set.
    .PARAMETER Parameters
        Per-action parameters (hashtable or object): MfaMethodIds, GrantIds, AppRoleAssignmentIds,
        ServicePrincipalIds, RuleIds, Delegations, TransportRuleIds, AddInIds, Protocols,
        MobileDeviceIds, RegisteredDeviceIds, CAPolicy { State, Controls, ExpiresHours }.
    .PARAMETER Confirmed
        The operator (or automation) confirmed the Critical actions.
    .PARAMETER Redacted
        Return the redacted rows (password replaced, copyField dropped) - for automation that forwards
        the results into an alert payload.
    .PARAMETER CaseId
        The BEC case the containment belongs to; results are appended to its run.
    .PARAMETER RunResults
        The run's results payload, used to resolve default targets. Loaded from CaseId when omitted.
    .PARAMETER DeploymentId
        Live-progress job id (New-CIPPAsyncDeployment, one row named after the UPN). When set, the
        row gets one step per selected action, updated as each runs - how a background run started
        by ExecBECRemediate reports back. The step messages carry the unredacted result text so the
        operator can still copy a new password; everything else stored stays redacted.
    .PARAMETER Headers
        CIPP request headers for logging.
    .PARAMETER APIName
        Logging API name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [string]$UserId,
        [Parameter(Mandatory = $true)][string]$UserPrincipalName,
        [string[]]$Actions = @(),
        $Parameters,
        [switch]$Confirmed,
        [switch]$Redacted,
        [string]$CaseId,
        $RunResults,
        [string]$DeploymentId,
        $Headers,
        [string]$APIName = 'BECRemediate'
    )

    $Catalog = Get-CIPPBecContainmentActions
    $Selected = if (-not $Actions -or @($Actions | Where-Object { $_ }).Count -eq 0) {
        @($Catalog | Where-Object { $_.DefaultSelected })
    } else {
        @(foreach ($Id in ($Actions | Where-Object { $_ } | Select-Object -Unique)) {
                $Match = $Catalog | Where-Object { $_.Id -ieq [string]$Id } | Select-Object -First 1
                if (-not $Match) { throw "Unknown containment action '$Id'" }
                $Match
            })
    }
    $Selected = @($Selected | Sort-Object -Property Order)
    $CriticalSelected = @($Selected | Where-Object { $_.Impact -eq 'Critical' })
    if ($CriticalSelected.Count -gt 0 -and -not $Confirmed) {
        throw "Confirmation is required: the selected actions include Critical changes ($($CriticalSelected.Id -join ', '))"
    }

    # Parameters may arrive as a hashtable or a deserialised object; member access on either is case-insensitive.
    $GetParam = { param($Name) $Parameters.$Name }
    $AsList = { param($Value) @($Value | Where-Object { $null -ne $_ -and "$_" -ne '' }) }

    $Rows = [System.Collections.Generic.List[object]]::new()
    $Add = {
        param($Action, $Target, $State, $Text, $Copy)
        $Rows.Add([pscustomobject]@{ Action = $Action; Target = $Target; state = $State; resultText = $Text; copyField = $Copy })
    }
    # Map a helper's own result rows onto the containment row shape
    $AddMany = {
        param($Action, $HelperRows)
        foreach ($Row in @($HelperRows | Where-Object { $_ })) {
            $Rows.Add([pscustomobject]@{ Action = $Action; Target = $Row.Target; state = $Row.state; resultText = $Row.resultText; copyField = $Row.copyField })
        }
    }

    if ($CaseId -and -not $RunResults) {
        try {
            $RunResults = (Get-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId -IncludeResults).Results
        } catch {
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "BEC run $CaseId could not be loaded for target resolution: $($_.Exception.Message)" -Sev 'Warning'
        }
    }

    # Progress reporting never stops the containment: the helpers swallow their own write failures.
    if ($DeploymentId) {
        try {
            $null = New-CIPPAsyncDeployment -JobId $DeploymentId -Names @($UserPrincipalName) -StepTitles @($Selected.Label) -Source 'BECRemediation' -TenantFilter $TenantFilter
            Set-CIPPAsyncDeploymentStatus -JobId $DeploymentId -Name $UserPrincipalName -Status 'running'
        } catch {
            Write-Information "BEC containment: could not create the progress row $DeploymentId`: $($_.Exception.Message)"
        }
    }
    $Finished = $false

    Set-CippBecCaseContext -CaseId $CaseId
    try {
        if (-not $UserId -and ($Selected.Id -contains 'RemoveOAuthGrants' -or $Selected.Id -contains 'TargetedCAPolicy')) {
            try {
                $UserId = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$([System.Web.HttpUtility]::UrlEncode($UserPrincipalName))?`$select=id" -tenantid $TenantFilter -AsApp $true).id
            } catch {
                Write-Information "BEC containment: could not resolve the object id of $UserPrincipalName`: $($_.Exception.Message)"
            }
        }

        for ($StepIndex = 0; $StepIndex -lt $Selected.Count; $StepIndex++) {
            $Action = $Selected[$StepIndex]
            $Id = $Action.Id
            $RowsBefore = $Rows.Count
            if ($DeploymentId) { Set-CIPPAsyncDeploymentStep -JobId $DeploymentId -Name $UserPrincipalName -StepIndex $StepIndex -StepStatus 'running' -Message 'In progress' }
            try {
                switch ($Id) {
                    'ResetPassword' {
                        $R = Set-CIPPResetPassword -UserID $UserPrincipalName -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers
                        & $Add $Id $UserPrincipalName ($R.state ?? 'success') ([string]$R.resultText) $R.copyField
                    }
                    'DisableAccount' {
                        try {
                            $R = Set-CIPPSignInState -UserID $UserPrincipalName -AccountEnabled $false -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers
                            & $Add $Id $UserPrincipalName 'success' ([string]$R) $null
                        } catch {
                            if ($_.Exception.Message -match 'AD Sync enabled') {
                                # the PATCH succeeded; the throw is the helper's way of flagging a synced account
                                & $Add $Id $UserPrincipalName 'warning' "Sign-in blocked in Entra ID for $UserPrincipalName, but the account is directory-synced: disable it on-premises too or the next sync re-enables it." $null
                            } else { throw }
                        }
                    }
                    'RevokeSessions' {
                        $R = Revoke-CIPPSessions -userid $UserPrincipalName -username $UserPrincipalName -Headers $Headers -APIName $APIName -tenantFilter $TenantFilter
                        & $Add $Id $UserPrincipalName 'success' ([string]$R) $null
                    }
                    'RemoveMFA' {
                        $MethodIds = & $AsList (& $GetParam 'MfaMethodIds')
                        # an empty string stands for "every method"; a single-element array survives assignment where @($null) collapses
                        if ($MethodIds.Count -eq 0) { $MethodIds = @('') }
                        foreach ($MethodId in $MethodIds) {
                            $Target = if ([string]::IsNullOrEmpty($MethodId)) { $UserPrincipalName } else { $MethodId }
                            try {
                                $R = if ([string]::IsNullOrEmpty($MethodId)) { Remove-CIPPUserMFA -UserPrincipalName $UserPrincipalName -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName } else { Remove-CIPPUserMFA -UserPrincipalName $UserPrincipalName -TenantFilter $TenantFilter -MethodId $MethodId -Headers $Headers -APIName $APIName }
                                $State = if ([string]$R -like '*No MFA method*') { 'info' } else { 'success' }
                                & $Add $Id $Target $State ([string]$R) $null
                            } catch {
                                # partial success is thrown as text that starts with 'Successfully removed ... However'
                                $State = if ($_.Exception.Message -match '(?i)^Successfully removed.*However') { 'warning' } else { 'error' }
                                & $Add $Id $Target $State $_.Exception.Message $null
                            }
                        }
                    }
                    'RemoveOAuthGrants' {
                        $GrantIds = & $AsList (& $GetParam 'GrantIds')
                        $AssignmentIds = & $AsList (& $GetParam 'AppRoleAssignmentIds')
                        if ($GrantIds.Count -eq 0 -and $AssignmentIds.Count -eq 0 -and $RunResults) {
                            $Flagged = @($RunResults.UserGrants | Where-Object { $_.Flagged -eq $true })
                            $GrantIds = @($Flagged | Where-Object { $_.Type -eq 'DelegatedGrant' } | ForEach-Object { $_.Id })
                            $AssignmentIds = @($Flagged | Where-Object { $_.Type -eq 'AppRoleAssignment' } | ForEach-Object { $_.Id })
                        }
                        if ($GrantIds.Count -eq 0 -and $AssignmentIds.Count -eq 0) { & $Add $Id $UserPrincipalName 'info' 'No flagged application consents to revoke' $null; break }
                        & $AddMany $Id (Remove-CIPPUserOAuthGrant -TenantFilter $TenantFilter -UserId $UserId -GrantIds $GrantIds -AppRoleAssignmentIds $AssignmentIds -Headers $Headers -APIName $APIName)
                    }
                    'DisableServicePrincipals' {
                        $SpIds = & $AsList (& $GetParam 'ServicePrincipalIds')
                        if ($SpIds.Count -eq 0 -and $RunResults) {
                            $SpIds = @($RunResults.UserGrants | Where-Object { $_.Risk -eq 'CatalogMatch' -and $_.ClientServicePrincipalId } | ForEach-Object { $_.ClientServicePrincipalId } | Select-Object -Unique)
                        }
                        if ($SpIds.Count -eq 0) { & $Add $Id $UserPrincipalName 'info' 'No catalog-matched applications to disable' $null; break }
                        foreach ($SpId in $SpIds) {
                            try {
                                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SpId" -tenantid $TenantFilter -type PATCH -body '{"accountEnabled":false}' -AsApp $true
                                & $Add $Id $SpId 'success' "Disabled service principal $SpId tenant-wide" $null
                            } catch { & $Add $Id $SpId 'error' "Failed to disable service principal $SpId`: $((Get-CippException -Exception $_).NormalizedError)" $null }
                        }
                    }
                    'DisableInboxRules' {
                        $RuleIds = & $AsList (& $GetParam 'RuleIds')
                        $HelperRows = if ($RuleIds.Count -gt 0) { Disable-CIPPInboxRules -TenantFilter $TenantFilter -UserPrincipalName $UserPrincipalName -RuleIds $RuleIds -Headers $Headers -APIName $APIName } else { Disable-CIPPInboxRules -TenantFilter $TenantFilter -UserPrincipalName $UserPrincipalName -Headers $Headers -APIName $APIName }
                        foreach ($Row in @($HelperRows)) { & $Add $Id $UserPrincipalName $Row.state $Row.resultText $null }
                    }
                    'ClearForwarding' {
                        $R = Set-CIPPForwarding -UserID $UserPrincipalName -Username $UserPrincipalName -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName -Disable $true
                        & $Add $Id $UserPrincipalName 'success' ([string]$R) $null
                    }
                    'ClearAutoReply' {
                        $R = Set-CIPPOutOfOffice -UserID $UserPrincipalName -TenantFilter $TenantFilter -State 'Disabled' -Headers $Headers -APIName $APIName
                        & $Add $Id $UserPrincipalName 'success' ([string]$R) $null
                    }
                    'RemoveDelegations' {
                        $Delegations = @((& $GetParam 'Delegations') | Where-Object { $_ })
                        if ($Delegations.Count -eq 0 -and $RunResults) { $Delegations = @($RunResults.Delegations | Where-Object { $_.Flagged -eq $true }) }
                        if ($Delegations.Count -eq 0) { & $Add $Id $UserPrincipalName 'info' 'No flagged delegations to remove' $null; break }
                        & $AddMany $Id (Remove-CIPPMailboxDelegation -TenantFilter $TenantFilter -UserPrincipalName $UserPrincipalName -Delegations $Delegations -Headers $Headers -APIName $APIName)
                    }
                    'DisableTransportRules' {
                        $RuleIds = & $AsList (& $GetParam 'TransportRuleIds')
                        if ($RuleIds.Count -eq 0 -and $RunResults) { $RuleIds = @($RunResults.TransportRulesFlagged | Where-Object { $_.ChangedInWindow -eq $true } | ForEach-Object { $_.Guid ?? $_.Identity ?? $_.Name }) }
                        if ($RuleIds.Count -eq 0) { & $Add $Id $TenantFilter 'info' 'No flagged transport rules changed in the window to disable' $null; break }
                        foreach ($RuleId in $RuleIds) {
                            try {
                                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Disable-TransportRule' -cmdParams @{ Identity = $RuleId; Confirm = $false } -useSystemMailbox $true
                                & $Add $Id $RuleId 'success' "Disabled transport rule '$RuleId'" $null
                            } catch { & $Add $Id $RuleId 'error' "Failed to disable transport rule '$RuleId': $((Get-CippException -Exception $_).NormalizedError)" $null }
                        }
                    }
                    'DisableMailboxAddIns' {
                        $AddInIds = & $AsList (& $GetParam 'AddInIds')
                        if ($AddInIds.Count -eq 0 -and $RunResults) { $AddInIds = @($RunResults.MailboxAddIns | Where-Object { $_.Flagged -eq $true } | ForEach-Object { $_.Identity ?? $_.AppId }) }
                        if ($AddInIds.Count -eq 0) { & $Add $Id $UserPrincipalName 'info' 'No flagged add-ins to disable' $null; break }
                        foreach ($AddInId in $AddInIds) {
                            try {
                                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Disable-App' -cmdParams @{ Identity = $AddInId; Mailbox = $UserPrincipalName; Confirm = $false } -Anchor $UserPrincipalName
                                & $Add $Id $AddInId 'success' "Disabled add-in $AddInId for $UserPrincipalName" $null
                            } catch { & $Add $Id $AddInId 'error' "Failed to disable add-in $AddInId`: $((Get-CippException -Exception $_).NormalizedError)" $null }
                        }
                    }
                    'BlockProtocols' {
                        $Protocols = @((& $AsList (& $GetParam 'Protocols')) | Select-Object -Unique)
                        if ($Protocols.Count -eq 0) { $Protocols = @('EWS', 'IMAP', 'POP', 'ActiveSync', 'SmtpAuth') }
                        # Set-CASMailbox switch per protocol; SmtpAuth maps to SmtpClientAuthenticationDisabled, which is inverted.
                        $ProtocolMap = @{ EWS = 'EWSEnabled'; IMAP = 'IMAPEnabled'; POP = 'POPEnabled'; ActiveSync = 'ActiveSyncEnabled'; OWA = 'OWAEnabled'; MAPI = 'MAPIEnabled'; ECP = 'ECPEnabled'; SmtpAuth = 'SmtpClientAuthenticationDisabled' }
                        $Unknown = @($Protocols | Where-Object { -not $ProtocolMap.ContainsKey([string]$_) })
                        if ($Unknown.Count -gt 0) { throw "Unknown protocol(s): $($Unknown -join ', ')" }
                        $CasParams = @{ Identity = $UserPrincipalName }
                        foreach ($Protocol in $Protocols) { $CasParams[$ProtocolMap[[string]$Protocol]] = ([string]$Protocol -eq 'SmtpAuth') }
                        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-CASMailbox' -cmdParams $CasParams -Anchor $UserPrincipalName
                        & $Add $Id $UserPrincipalName 'success' "Disabled $($Protocols -join ', ') for $UserPrincipalName" $null
                    }
                    { $_ -in @('BlockMobileDevices', 'RemoveMobileDevices') } {
                        $Picked = @((& $GetParam 'MobileDeviceIds') | Where-Object { $_ } | ForEach-Object { [string]$_ })
                        $Known = @($RunResults.SuspectUserDevices | Where-Object { $_ })
                        # The block list takes the DeviceID and the removal takes the partnership Guid, so a pick the run's
                        # inventory does not know (no run, or an API caller) is looked up on the mailbox rather than guessed.
                        $Unresolved = @($Picked | Where-Object { $_ -notin @($Known.DeviceID) -and $_ -notin @($Known.Guid) -and $_ -notin @($Known.Identity) })
                        if ($Known.Count -eq 0 -or $Unresolved.Count -gt 0) {
                            $Live = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MobileDevice' -cmdParams @{ Mailbox = $UserPrincipalName } -Anchor $UserPrincipalName | Where-Object { $_ })
                            $Known = @($Known) + @($Live | Where-Object { $_.Guid -notin @($Known.Guid) })
                        }
                        $DeviceRows = if ($Picked.Count -gt 0) { @($Known | Where-Object { $_.DeviceID -in $Picked -or $_.Guid -in $Picked -or $_.Identity -in $Picked }) } else { @($Known) }
                        foreach ($Missing in @($Picked | Where-Object { $_ -notin @($DeviceRows.DeviceID) -and $_ -notin @($DeviceRows.Guid) -and $_ -notin @($DeviceRows.Identity) })) {
                            & $Add $Id $Missing 'error' "No mobile device partnership '$Missing' found on $UserPrincipalName" $null
                        }
                        if ($DeviceRows.Count -eq 0) { if ($Picked.Count -eq 0) { & $Add $Id $UserPrincipalName 'info' 'No mobile device partnerships found' $null }; break }
                        foreach ($Device in $DeviceRows) {
                            $Target = [string]($Device.DeviceID ?? $Device.Guid)
                            try {
                                $R = if ($Id -eq 'BlockMobileDevices') { Set-CIPPMobileDevice -Headers $Headers -Quarantine 'true' -UserId $UserPrincipalName -DeviceId ([string]$Device.DeviceID) -TenantFilter $TenantFilter -Delete 'false' -Guid ([string]$Device.Guid) -APIName $APIName } else { Set-CIPPMobileDevice -Headers $Headers -Quarantine 'false' -UserId $UserPrincipalName -DeviceId ([string]$Device.DeviceID) -TenantFilter $TenantFilter -Delete 'true' -Guid ([string]$Device.Guid) -APIName $APIName }
                                & $Add $Id $Target ($(if ([string]$R -like 'Failed*') { 'error' } else { 'success' })) ([string]$R) $null
                            } catch { & $Add $Id $Target 'error' $_.Exception.Message $null }
                        }
                    }
                    { $_ -in @('DisableRegisteredDevices', 'RemoveRegisteredDevices') } {
                        $DeviceIds = & $AsList (& $GetParam 'RegisteredDeviceIds')
                        if ($DeviceIds.Count -eq 0 -and $RunResults) { $DeviceIds = @($RunResults.RegisteredDevices | Where-Object { $_.RegisteredInWindow -eq $true } | ForEach-Object { $_.id }) }
                        if ($DeviceIds.Count -eq 0) { & $Add $Id $UserPrincipalName 'info' 'No registered devices from the window to act on' $null; break }
                        $DeviceAction = if ($Id -eq 'DisableRegisteredDevices') { 'Disable' } else { 'Delete' }
                        foreach ($DeviceId in $DeviceIds) {
                            try {
                                $R = Set-CIPPDeviceState -Action $DeviceAction -DeviceID $DeviceId -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
                                & $Add $Id $DeviceId 'success' ([string]$R) $null
                            } catch { & $Add $Id $DeviceId 'error' $_.Exception.Message $null }
                        }
                    }
                    'TargetedCAPolicy' {
                        $Policy = & $GetParam 'CAPolicy'
                        $State = if ([string]$Policy.State -in @('enabled', 'enabledForReportingButNotEnabled')) { [string]$Policy.State } elseif ([string]$Policy.State -eq 'reportOnly') { 'enabledForReportingButNotEnabled' } else { 'enabled' }
                        $Controls = if ([string]$Policy.Controls -eq 'mfaAndCompliantDevice') { 'mfaAndCompliantDevice' } else { 'mfa' }
                        $Hours = [int]($Policy.ExpiresHours ?? 24)
                        if ($Hours -lt 1 -or $Hours -gt 168) { $Hours = 24 }
                        if (-not $UserId) { throw "The user's object id is required to create a targeted Conditional Access policy" }
                        $R = New-CIPPBecTargetedCAPolicy -TenantFilter $TenantFilter -UserId $UserId -UserPrincipalName $UserPrincipalName -State $State -Controls $Controls -ExpiresHours $Hours -CaseId $CaseId -Headers $Headers -APIName $APIName
                        & $Add $Id $UserPrincipalName ($(if ([string]$R -like '*WARNING*') { 'warning' } else { 'success' })) ([string]$R) $null
                    }
                    'DisableOneDriveSharing' {
                        $R = Set-CIPPOneDriveSharing -UserId $UserPrincipalName -TenantFilter $TenantFilter -SharingCapability 'Disabled' -APIName $APIName -Headers $Headers
                        & $Add $Id $UserPrincipalName ($(if ([string]$R -like '*Successfully*') { 'success' } else { 'error' })) ([string]$R) $null
                    }
                    'RemoveSharingLinks' {
                        # Explicit picks first, else the item URL of every sharing change the run recorded.
                        $Urls = & $AsList (& $GetParam 'SharingLinkUrls')
                        if ($Urls.Count -eq 0 -and $RunResults) {
                            $Urls = @($RunResults.SharingChanges | ForEach-Object { $_.ItemUrl } | Where-Object { $_ } | Select-Object -Unique)
                        }
                        $Urls = @($Urls | Where-Object { $_ } | Select-Object -Unique)
                        if ($Urls.Count -eq 0) { & $Add $Id $UserPrincipalName 'info' 'No sharing links from the run to remove' $null; break }
                        & $AddMany $Id (Remove-CIPPBecSharingLinks -TenantFilter $TenantFilter -UserPrincipalName $UserPrincipalName -ItemUrls $Urls -Headers $Headers -APIName $APIName)
                    }
                    'BlockSenders' {
                        # Explicit picks first, else every distinct phishing-shaped sender the run recorded.
                        $Senders = & $AsList (& $GetParam 'BlockSenders')
                        if ($Senders.Count -eq 0 -and $RunResults) {
                            $Senders = @($RunResults.ReceivedMailFindings | ForEach-Object { $_.SenderAddress } | Where-Object { $_ } | Select-Object -Unique)
                        }
                        $Senders = @($Senders | Where-Object { $_ } | Select-Object -Unique)
                        if ($Senders.Count -eq 0) { & $Add $Id $TenantFilter 'info' 'No phishing-shaped senders from the run to block' $null; break }
                        # One New-TenantAllowBlockListItems call takes the whole set; emit a row per sender for the results table.
                        try {
                            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-TenantAllowBlockListItems' -cmdParams @{
                                Entries      = @($Senders)
                                ListType     = 'Sender'
                                Block        = $true
                                NoExpiration = $true
                                Notes        = "Blocked from BEC case $CaseId"
                            }
                            foreach ($Address in $Senders) { & $Add $Id $Address 'success' "Added $Address to the tenant Block list (Sender)" $null }
                        } catch {
                            $BlockError = Get-CippException -Exception $_
                            foreach ($Address in $Senders) { & $Add $Id $Address 'error' "Failed to block $Address`: $($BlockError.NormalizedError)" $null }
                        }
                    }
                    default { & $Add $Id $UserPrincipalName 'error' "Action '$Id' has no implementation" $null }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                & $Add $Id $UserPrincipalName 'error' "$($Action.Label) failed: $($ErrorMessage.NormalizedError)" $null
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "BEC containment action $Id failed for $UserPrincipalName`: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
            }
            if ($DeploymentId) {
                $StepRows = @(for ($i = $RowsBefore; $i -lt $Rows.Count; $i++) { $Rows[$i] })
                $StepStatus = if (@($StepRows | Where-Object { $_.state -eq 'error' }).Count -gt 0) { 'failed' } else { 'succeeded' }
                $StepMessage = if ($StepRows.Count -gt 0) { @($StepRows.resultText) -join "`n" } else { 'Done' }
                Set-CIPPAsyncDeploymentStep -JobId $DeploymentId -Name $UserPrincipalName -StepIndex $StepIndex -StepStatus $StepStatus -Message $StepMessage
            }
        }

        # Persist and log a redacted copy: the password (copyField) must never reach the logbook or the run.
        $RedactedRows = @(foreach ($Row in $Rows) {
                $Text = [string]$Row.resultText
                if ($Row.copyField) { $Text = $Text.Replace([string]$Row.copyField, '[redacted]') }
                [pscustomobject]@{ Action = $Row.Action; Target = $Row.Target; state = $Row.state; resultText = $Text }
            })
        $Summary = "Executed BEC containment for $UserPrincipalName ($($Selected.Id -join ', '))$(if ($CaseId) { " [case $CaseId]" })"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Summary -Sev 'Info' -LogData @($RedactedRows)
        if ($CaseId) {
            try {
                $Run = Get-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId
                if ($Run) {
                    $By = if ($Headers -and $Headers.'x-ms-client-principal') { try { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } catch { 'CIPP' } } elseif ($Headers -is [string]) { $Headers } else { 'CIPP' }
                    $History = @($Run.Containment | Where-Object { $_ }) + @([pscustomobject]@{ At = (Get-Date).ToUniversalTime().ToString('o'); By = [string]$By; Actions = @($Selected.Id); Results = $RedactedRows })
                    $null = Set-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId -Properties @{ Containment = $History; LastContainmentAt = (Get-Date).ToUniversalTime().ToString('o') }
                }
            } catch {
                Write-Information "BEC containment: could not append the result to run $CaseId`: $($_.Exception.Message)"
            }
        }
        if ($DeploymentId) {
            $OverallStatus = if (@($Rows | Where-Object { $_.state -eq 'error' }).Count -gt 0) { 'failed' } else { 'succeeded' }
            Set-CIPPAsyncDeploymentStatus -JobId $DeploymentId -Name $UserPrincipalName -Status $OverallStatus
        }
        $Finished = $true
    } finally {
        # an unexpected throw must not leave the progress view spinning
        if ($DeploymentId -and -not $Finished) { Set-CIPPAsyncDeploymentStatus -JobId $DeploymentId -Name $UserPrincipalName -Status 'failed' }
        Set-CippBecCaseContext -CaseId $null
    }
    return $(if ($Redacted) { $RedactedRows } else { $Rows.ToArray() })
}
