BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    # Every mutator the dispatcher can reach is a stub so a run can prove exactly which ones are invoked.
    function Set-CIPPResetPassword { param($UserID, $DisplayName, $TenantFilter, $APIName, $Headers, $forceChangePasswordNextSignIn) }
    function Set-CIPPSignInState { param($UserID, $AccountEnabled, $TenantFilter, $APIName, $Headers) }
    function Revoke-CIPPSessions { param($userid, $username, $Headers, $APIName, $tenantFilter) }
    function Remove-CIPPUserMFA { param($UserPrincipalName, $TenantFilter, $MethodId, $Headers, $APIName) }
    function Remove-CIPPUserOAuthGrant { param($TenantFilter, $UserId, $GrantIds, $AppRoleAssignmentIds, $Headers, $APIName) }
    function Disable-CIPPInboxRules { param($TenantFilter, $UserPrincipalName, $RuleIds, $Headers, $APIName) }
    function Set-CIPPForwarding { param($UserID, $ForwardingSMTPAddress, $TenantFilter, $Username, $Headers, $APIName, $Forward, $KeepCopy, $Disable) }
    function Set-CIPPOutOfOffice { param($UserID, $InternalMessage, $ExternalMessage, $TenantFilter, $State, $APIName, $Headers) }
    function Remove-CIPPMailboxDelegation { param($TenantFilter, $UserPrincipalName, $Delegations, $Headers, $APIName) }
    function Set-CIPPMobileDevice { param($Headers, $Quarantine, $UserId, $DeviceId, $TenantFilter, $Delete, $Guid, $APIName) }
    function Set-CIPPDeviceState { param($Action, $DeviceID, $TenantFilter, $Headers, $APIName) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body, $AsApp) }
    function New-CIPPBecTargetedCAPolicy { param($TenantFilter, $UserId, $UserPrincipalName, $State, $Controls, $ExpiresHours, $CaseId, $Headers, $APIName) }
    function Set-CIPPOneDriveSharing { param($UserId, $TenantFilter, $SharingCapability, $APIName, $Headers, $URL) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $noPagination) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Anchor, $useSystemMailbox, $NoAuthCheck) }
    function Remove-CIPPBecSharingLinks { param($TenantFilter, $UserPrincipalName, $ItemUrls, $Headers, $APIName) }
    function Write-LogMessage { param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
    function Set-CippBecCaseContext { param($CaseId) }
    function Get-CIPPBecReport { param($TenantFilter, $CaseId, $UserId, [switch]$IncludeResults) }
    function Set-CIPPBecReport { param($TenantFilter, $CaseId, $Properties, $Results, [switch]$Replace) }
    function New-CIPPAsyncDeployment { param($JobId, $Names, $StepTitles, $Source, $TaskId, $TenantFilter) }
    function Set-CIPPAsyncDeploymentStep { param($JobId, $Name, $StepIndex, $StepStatus, $Message) }
    function Set-CIPPAsyncDeploymentStatus { param($JobId, $Name, $Status, $Logs) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecContainmentActions.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Invoke-CIPPBecContainment.ps1')

    $script:Mutators = @('Set-CIPPResetPassword', 'Set-CIPPSignInState', 'Revoke-CIPPSessions', 'Remove-CIPPUserMFA', 'Remove-CIPPUserOAuthGrant', 'Disable-CIPPInboxRules', 'Set-CIPPForwarding', 'Set-CIPPOutOfOffice', 'Remove-CIPPMailboxDelegation', 'Set-CIPPMobileDevice', 'Set-CIPPDeviceState', 'New-CIPPBecTargetedCAPolicy', 'Set-CIPPOneDriveSharing', 'New-ExoRequest', 'New-GraphPOSTRequest')
    $script:Run = [pscustomobject]@{
        UserGrants            = @([pscustomobject]@{ Id = 'g-bad'; Type = 'DelegatedGrant'; Flagged = $true; Risk = 'CatalogMatch'; ClientServicePrincipalId = 'sp-bad' }, [pscustomobject]@{ Id = 'g-ok'; Type = 'DelegatedGrant'; Flagged = $false; Risk = 'Low' }, [pscustomobject]@{ Id = 'a-bad'; Type = 'AppRoleAssignment'; Flagged = $true; Risk = 'CatalogMatch'; ClientServicePrincipalId = 'sp-bad' })
        Delegations           = @([pscustomobject]@{ PermissionType = 'FullAccess'; Trustee = 'outsider@example.org'; Resource = 'victim@contoso.com'; Identity = 'victim@contoso.com'; Flagged = $true }, [pscustomobject]@{ PermissionType = 'SendAs'; Trustee = 'assistant@contoso.com'; Resource = 'victim@contoso.com'; Flagged = $false })
        NewRules              = @([pscustomobject]@{ Name = 'Hide'; Identity = 'r1' })
        TransportRulesFlagged = @([pscustomobject]@{ Guid = 'tr-1'; Name = 'Exfil'; ChangedInWindow = $true }, [pscustomobject]@{ Guid = 'tr-2'; Name = 'Old'; ChangedInWindow = $false })
        MailboxAddIns         = @([pscustomobject]@{ Identity = 'addin-1'; Flagged = $true })
        SuspectUserDevices    = @([pscustomobject]@{ DeviceID = 'dev-1'; Guid = 'guid-1'; DeviceModel = 'Phone' })
        RegisteredDevices     = @([pscustomobject]@{ id = 'entra-1'; RegisteredInWindow = $true }, [pscustomobject]@{ id = 'entra-old'; RegisteredInWindow = $false })
        MailboxState          = [pscustomobject]@{ HasForwarding = $true; ForwardingSmtpAddress = 'smtp:x@example.org'; AutoReplyState = 'Enabled' }
        ReceivedMailFindings  = @([pscustomobject]@{ FindingType = 'Typosquat'; SenderAddress = 'ceo@contos0.com'; SenderDomain = 'contos0.com' }, [pscustomobject]@{ FindingType = 'SubjectPattern'; SenderAddress = 'billing@evil.example'; SenderDomain = 'evil.example' }, [pscustomobject]@{ FindingType = 'Keyword'; SenderAddress = 'ceo@contos0.com'; SenderDomain = 'contos0.com' })
        SharingChanges        = @([pscustomobject]@{ Operation = 'AnonymousLinkCreated'; ItemUrl = 'https://contoso-my.sharepoint.com/personal/victim/Documents/payroll.xlsx'; FileName = 'payroll.xlsx' }, [pscustomobject]@{ Operation = 'CompanyLinkCreated'; ItemUrl = 'https://contoso-my.sharepoint.com/personal/victim/Documents/contracts.docx'; FileName = 'contracts.docx' })
    }
}

Describe 'Invoke-CIPPBecContainment' {
    BeforeEach {
        foreach ($Name in $script:Mutators) { Mock $Name { "$Name ran" } }
        Mock Set-CIPPResetPassword { [pscustomobject]@{ resultText = 'Successfully reset the password. The new password is Hunter2!'; copyField = 'Hunter2!'; state = 'success' } }
        Mock Remove-CIPPUserOAuthGrant { @(foreach ($G in $GrantIds) { [pscustomobject]@{ Target = $G; state = 'success'; resultText = "Deleted $G" } }) + @(foreach ($A in $AppRoleAssignmentIds) { [pscustomobject]@{ Target = $A; state = 'success'; resultText = "Deleted $A" } }) }
        Mock Disable-CIPPInboxRules { @([pscustomobject]@{ resultText = 'Disabled 1 inbox rule(s)'; state = 'success' }) }
        Mock Remove-CIPPMailboxDelegation { @(foreach ($D in $Delegations) { [pscustomobject]@{ Target = "$($D.PermissionType) $($D.Trustee)"; state = 'success'; resultText = 'removed' } }) }
        Mock Write-LogMessage { }
        Mock Set-CippBecCaseContext { }
        Mock Get-CIPPBecReport { [pscustomobject]@{ CaseId = 'BEC-1'; Containment = @() } }
        Mock Set-CIPPBecReport { }
        Mock New-GraphGetRequest { [pscustomobject]@{ id = 'user-guid' } }
        Mock Remove-CIPPBecSharingLinks { @(foreach ($Url in $ItemUrls) { [pscustomobject]@{ Target = $Url; state = 'success'; resultText = "Removed link on $Url" } }) }
    }

    It 'reports one progress step per action, in run order, when given a DeploymentId' {
        Mock New-CIPPAsyncDeployment { $JobId }
        Mock Set-CIPPAsyncDeploymentStep { }
        Mock Set-CIPPAsyncDeploymentStatus { }
        Mock Revoke-CIPPSessions { throw 'Graph said no' }
        $null = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserId 'u1' -UserPrincipalName 'victim@contoso.com' -Actions @('ClearAutoReply', 'ResetPassword', 'RevokeSessions') -Confirmed -DeploymentId 'job-1'
        Should -Invoke New-CIPPAsyncDeployment -Times 1 -ParameterFilter { $JobId -eq 'job-1' -and $Names -contains 'victim@contoso.com' -and (@($StepTitles) -join '|') -eq 'Reset password|Revoke sessions|Turn off automatic replies' }
        Should -Invoke Set-CIPPAsyncDeploymentStep -Times 3 -ParameterFilter { $StepStatus -eq 'running' }
        # the step message keeps the password so a background run can still hand it to the operator
        Should -Invoke Set-CIPPAsyncDeploymentStep -Times 1 -ParameterFilter { $StepIndex -eq 0 -and $StepStatus -eq 'succeeded' -and $Message -match 'Hunter2!' }
        Should -Invoke Set-CIPPAsyncDeploymentStep -Times 1 -ParameterFilter { $StepIndex -eq 1 -and $StepStatus -eq 'failed' -and $Message -match 'Graph said no' }
        Should -Invoke Set-CIPPAsyncDeploymentStep -Times 1 -ParameterFilter { $StepIndex -eq 2 -and $StepStatus -eq 'succeeded' }
        Should -Invoke Set-CIPPAsyncDeploymentStatus -Times 1 -ParameterFilter { $Status -eq 'running' }
        Should -Invoke Set-CIPPAsyncDeploymentStatus -Times 1 -ParameterFilter { $Status -eq 'failed' }
    }

    It 'loads the case results itself when only a CaseId is given' {
        Mock Get-CIPPBecReport { [pscustomobject]@{ CaseId = 'BEC-1'; Containment = @(); Results = $script:Run } } -ParameterFilter { $IncludeResults.IsPresent }
        $null = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserId 'u1' -UserPrincipalName 'victim@contoso.com' -Actions @('RemoveOAuthGrants') -Confirmed -CaseId 'BEC-1'
        Should -Invoke Remove-CIPPUserOAuthGrant -Times 1 -ParameterFilter { @($GrantIds) -contains 'g-bad' -and @($AppRoleAssignmentIds) -contains 'a-bad' }
    }

    It 'touches no progress row without a DeploymentId' {
        Mock Set-CIPPAsyncDeploymentStep { }
        Mock Set-CIPPAsyncDeploymentStatus { }
        $null = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('RevokeSessions')
        Should -Invoke Set-CIPPAsyncDeploymentStep -Times 0
        Should -Invoke Set-CIPPAsyncDeploymentStatus -Times 0
    }

    It 'runs the built-in default set in order when no actions are selected' {
        $Rows = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserId 'u1' -UserPrincipalName 'victim@contoso.com' -Confirmed
        @($Rows.Action | Select-Object -Unique) | Should -Be @('ResetPassword', 'DisableAccount', 'RevokeSessions', 'RemoveMFA', 'DisableInboxRules', 'BlockProtocols')
        Should -Invoke Set-CIPPResetPassword -Times 1
        Should -Invoke Set-CIPPSignInState -Times 1 -ParameterFilter { $AccountEnabled -eq $false }
        Should -Invoke Revoke-CIPPSessions -Times 1
        Should -Invoke Remove-CIPPUserMFA -Times 1 -ParameterFilter { -not $MethodId }
        Should -Invoke Disable-CIPPInboxRules -Times 1
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter { $cmdlet -eq 'Set-CASMailbox' -and $cmdParams.EWSEnabled -eq $false -and $cmdParams.IMAPEnabled -eq $false -and $cmdParams.POPEnabled -eq $false -and $cmdParams.ActiveSyncEnabled -eq $false -and $cmdParams.SmtpClientAuthenticationDisabled -eq $true }
        Should -Invoke Set-CIPPOneDriveSharing -Times 0
        Should -Invoke Remove-CIPPUserOAuthGrant -Times 0
        ($Rows | Where-Object { $_.Action -eq 'ResetPassword' }).copyField | Should -Be 'Hunter2!'
    }

    It 'refuses Critical actions without confirmation and names them' {
        { Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' } | Should -Throw '*Confirmation is required*ResetPassword*'
        { Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('RevokeSessions') } | Should -Not -Throw
        foreach ($Name in $script:Mutators) { if ($Name -ne 'Revoke-CIPPSessions') { Should -Invoke $Name -Times 0 } }
    }

    It 'rejects an unknown action before doing anything' {
        { Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('RevokeSessions', 'FormatDisk') -Confirmed } | Should -Throw "*Unknown containment action 'FormatDisk'*"
        Should -Invoke Revoke-CIPPSessions -Times 0
    }

    It 'prefers explicit parameters over the run''s flagged items' {
        $Rows = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserId 'u1' -UserPrincipalName 'victim@contoso.com' -Actions @('RemoveOAuthGrants', 'DisableTransportRules', 'BlockProtocols', 'RemoveMFA') -Confirmed -RunResults $script:Run -Parameters @{ GrantIds = @('g-ok'); TransportRuleIds = @('tr-2'); Protocols = @('IMAP'); MfaMethodIds = @('m1', 'm2') }
        Should -Invoke Remove-CIPPUserOAuthGrant -Times 1 -ParameterFilter { $GrantIds -contains 'g-ok' -and $GrantIds -notcontains 'g-bad' -and $UserId -eq 'u1' }
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter { $cmdlet -eq 'Disable-TransportRule' -and $cmdParams.Identity -eq 'tr-2' }
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter { $cmdlet -eq 'Set-CASMailbox' -and $cmdParams.IMAPEnabled -eq $false -and $cmdParams.Keys.Count -eq 2 }
        Should -Invoke Remove-CIPPUserMFA -Times 2
        Should -Invoke Remove-CIPPUserMFA -Times 1 -ParameterFilter { $MethodId -eq 'm2' }
        ($Rows | Where-Object { $_.Action -eq 'RemoveOAuthGrants' }).Target | Should -Be 'g-ok'
    }

    It 'reads parameters from a deserialised object as well as a hashtable' {
        $Params = [pscustomobject]@{ protocols = @('OWA', 'MAPI') }
        $null = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('BlockProtocols') -Parameters $Params
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter { $cmdlet -eq 'Set-CASMailbox' -and $cmdParams.OWAEnabled -eq $false -and $cmdParams.MAPIEnabled -eq $false }
    }

    It 'keeps going when one action fails and reports it as an error row' {
        Mock Revoke-CIPPSessions { throw 'Graph is down' }
        $Rows = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('RevokeSessions', 'DisableOneDriveSharing', 'ClearAutoReply')
        ($Rows | Where-Object { $_.Action -eq 'RevokeSessions' }).state | Should -Be 'error'
        ($Rows | Where-Object { $_.Action -eq 'RevokeSessions' }).resultText | Should -Match 'Graph is down'
        Should -Invoke Set-CIPPOneDriveSharing -Times 1
        Should -Invoke Set-CIPPOutOfOffice -Times 1 -ParameterFilter { $State -eq 'Disabled' }
        ($Rows | Where-Object { $_.Action -eq 'ClearAutoReply' }).state | Should -Be 'success'
    }

    It 'maps the AD-sync throw of Set-CIPPSignInState to a warning, not an error' {
        Mock Set-CIPPSignInState { throw 'WARNING: User victim@contoso.com is AD Sync enabled. Please enable/disable in the local AD.' }
        $Rows = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('DisableAccount') -Confirmed
        $Rows[0].state | Should -Be 'warning'
        $Rows[0].resultText | Should -Match 'directory-synced'
    }

    It 'maps a partial MFA removal to a warning and a full failure to an error' {
        Mock Remove-CIPPUserMFA { throw 'Successfully removed MFA methods (phone) for user victim@contoso.com. However, failed to remove (fido2). User may still have MFA methods assigned.' }
        (Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('RemoveMFA'))[0].state | Should -Be 'warning'
        Mock Remove-CIPPUserMFA { throw 'Failed to remove MFA methods (phone) for user victim@contoso.com' }
        (Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('RemoveMFA'))[0].state | Should -Be 'error'
    }

    It 'never writes the password to the log or the stored run, but still returns it to the caller' {
        $Rows = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('ResetPassword') -Confirmed -CaseId 'BEC-1'
        $Rows[0].copyField | Should -Be 'Hunter2!'
        $Rows[0].resultText | Should -Match 'Hunter2!'
        Should -Invoke Write-LogMessage -Times 0 -ParameterFilter { ($LogData | ConvertTo-Json -Depth 5) -match 'Hunter2' }
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $LogData -and ($LogData | ConvertTo-Json -Depth 5) -match '\[redacted\]' }
        Should -Invoke Set-CIPPBecReport -Times 0 -ParameterFilter { ($Properties.Containment | ConvertTo-Json -Depth 6) -match 'Hunter2' }
        Should -Invoke Set-CIPPBecReport -Times 1 -ParameterFilter { ($Properties.Containment | ConvertTo-Json -Depth 6) -match '\[redacted\]' -and -not ($Properties.Containment | ConvertTo-Json -Depth 6).Contains('copyField') }
    }

    It 'reports info rows instead of acting when a targeted action has nothing to target' {
        $Rows = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('RemoveOAuthGrants', 'RemoveDelegations', 'DisableTransportRules') -Confirmed -RunResults ([pscustomobject]@{ UserGrants = @(); Delegations = @(); TransportRulesFlagged = @() })
        @($Rows | Where-Object { $_.state -eq 'info' }).Count | Should -Be 3
        Should -Invoke Remove-CIPPUserOAuthGrant -Times 0
        Should -Invoke Remove-CIPPMailboxDelegation -Times 0
        Should -Invoke New-ExoRequest -Times 0
    }

    It 'resolves the user object id when a Graph action needs it and none was supplied' {
        $null = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('TargetedCAPolicy') -Parameters @{ CAPolicy = @{ State = 'reportOnly'; Controls = 'mfaAndCompliantDevice'; ExpiresHours = 4 } }
        Should -Invoke New-GraphGetRequest -Times 1
        Should -Invoke New-CIPPBecTargetedCAPolicy -Times 1 -ParameterFilter { $UserId -eq 'user-guid' -and $State -eq 'enabledForReportingButNotEnabled' -and $Controls -eq 'mfaAndCompliantDevice' -and $ExpiresHours -eq 4 }
    }

    It 'disables the run''s catalog-matched applications and deletes in-window devices through the platform helpers' {
        $Rows = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('DisableServicePrincipals', 'RemoveRegisteredDevices', 'DisableMailboxAddIns') -Confirmed -RunResults $script:Run
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { $uri -like '*/servicePrincipals/sp-bad' -and $type -eq 'PATCH' -and $body -match '"accountEnabled":false' }
        Should -Invoke Set-CIPPDeviceState -Times 1 -ParameterFilter { $Action -eq 'Delete' -and $DeviceID -eq 'entra-1' }
        Should -Invoke Set-CIPPDeviceState -Times 0 -ParameterFilter { $DeviceID -eq 'entra-old' }
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter { $cmdlet -eq 'Disable-App' -and $cmdParams.Identity -eq 'addin-1' -and $cmdParams.Mailbox -eq 'victim@contoso.com' }
        @($Rows | Where-Object { $_.state -eq 'success' }).Count | Should -Be 3
    }

    It 'returns the redacted rows for automation with -Redacted' {
        $Rows = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('ResetPassword') -Confirmed -Redacted
        $Rows[0].resultText | Should -Match '\[redacted\]'
        $Rows[0].resultText | Should -Not -Match 'Hunter2'
        $Rows[0].PSObject.Properties['copyField'] | Should -BeNullOrEmpty
    }

    It 'looks a mobile device up on the mailbox when the run does not know it, so removal gets the partnership Guid' {
        Mock New-ExoRequest { @([pscustomobject]@{ DeviceId = 'dev-live'; Guid = 'guid-live'; Identity = 'victim\ExchangeActiveSyncDevices\dev-live'; DeviceModel = 'Phone' }) } -ParameterFilter { $cmdlet -eq 'Get-MobileDevice' }
        $Rows = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('RemoveMobileDevices') -Parameters @{ MobileDeviceIds = @('dev-live', 'dev-missing') }
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter { $cmdlet -eq 'Get-MobileDevice' -and $cmdParams.Mailbox -eq 'victim@contoso.com' }
        Should -Invoke Set-CIPPMobileDevice -Times 1 -ParameterFilter { $Delete -eq 'true' -and $Guid -eq 'guid-live' -and $DeviceId -eq 'dev-live' }
        Should -Invoke Set-CIPPMobileDevice -Times 1
        ($Rows | Where-Object { $_.Target -eq 'dev-missing' }).state | Should -Be 'error'
    }

    It 'uses the run''s device inventory without a live lookup when it covers the picks' {
        $null = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('BlockMobileDevices') -RunResults $script:Run -Parameters @{ MobileDeviceIds = @('dev-1') }
        Should -Invoke New-ExoRequest -Times 0 -ParameterFilter { $cmdlet -eq 'Get-MobileDevice' }
        Should -Invoke Set-CIPPMobileDevice -Times 1 -ParameterFilter { $Quarantine -eq 'true' -and $DeviceId -eq 'dev-1' -and $Guid -eq 'guid-1' }
    }

    It 'sets and clears the case log context' {
        $null = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('RevokeSessions') -CaseId 'BEC-9'
        Should -Invoke Set-CippBecCaseContext -Times 1 -ParameterFilter { $CaseId -eq 'BEC-9' }
        Should -Invoke Set-CippBecCaseContext -Times 1 -ParameterFilter { [string]::IsNullOrEmpty($CaseId) }
    }

    It 'blocks the distinct phishing senders from the run in one tenant Block-list call' {
        Mock New-ExoRequest { }
        $Rows = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('BlockSenders') -RunResults $script:Run
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter { $cmdlet -eq 'New-TenantAllowBlockListItems' -and $cmdParams.ListType -eq 'Sender' -and $cmdParams.Block -eq $true -and $cmdParams.NoExpiration -eq $true -and @($cmdParams.Entries).Count -eq 2 -and $cmdParams.Entries -contains 'ceo@contos0.com' -and $cmdParams.Entries -contains 'billing@evil.example' }
        @($Rows | Where-Object { $_.Action -eq 'BlockSenders' -and $_.state -eq 'success' }).Count | Should -Be 2
    }

    It 'prefers explicit sender picks over the run findings when blocking senders' {
        Mock New-ExoRequest { }
        $null = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('BlockSenders') -RunResults $script:Run -Parameters @{ BlockSenders = @('only@picked.example') }
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter { @($cmdParams.Entries) -eq 'only@picked.example' }
    }

    It 'reports an info row and blocks nothing when the run found no phishing senders' {
        Mock New-ExoRequest { }
        $Rows = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('BlockSenders') -RunResults ([pscustomobject]@{ ReceivedMailFindings = @() })
        $Rows[0].state | Should -Be 'info'
        Should -Invoke New-ExoRequest -Times 0
    }

    It 'reports an error row per sender when the tenant Block-list call fails' {
        Mock New-ExoRequest { throw 'EXO unavailable' }
        $Rows = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('BlockSenders') -RunResults $script:Run
        @($Rows | Where-Object { $_.Action -eq 'BlockSenders' -and $_.state -eq 'error' }).Count | Should -Be 2
        ($Rows | Where-Object { $_.Action -eq 'BlockSenders' })[0].resultText | Should -Match 'EXO unavailable'
    }

    It 'removes the sharing links recorded in the run' {
        $Rows = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('RemoveSharingLinks') -RunResults $script:Run
        Should -Invoke Remove-CIPPBecSharingLinks -Times 1 -ParameterFilter { @($ItemUrls).Count -eq 2 -and $ItemUrls -contains 'https://contoso-my.sharepoint.com/personal/victim/Documents/payroll.xlsx' }
        @($Rows | Where-Object { $_.Action -eq 'RemoveSharingLinks' -and $_.state -eq 'success' }).Count | Should -Be 2
    }

    It 'prefers explicit sharing-link URLs over the run findings' {
        $null = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('RemoveSharingLinks') -RunResults $script:Run -Parameters @{ SharingLinkUrls = @('https://contoso-my.sharepoint.com/personal/victim/Documents/only.txt') }
        Should -Invoke Remove-CIPPBecSharingLinks -Times 1 -ParameterFilter { @($ItemUrls) -eq 'https://contoso-my.sharepoint.com/personal/victim/Documents/only.txt' }
    }

    It 'reports an info row and removes nothing when the run recorded no sharing changes' {
        $Rows = Invoke-CIPPBecContainment -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('RemoveSharingLinks') -RunResults ([pscustomobject]@{ SharingChanges = @() })
        $Rows[0].state | Should -Be 'info'
        Should -Invoke Remove-CIPPBecSharingLinks -Times 0
    }
}
