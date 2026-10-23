[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Stubs exist only so Pester can mock them.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Stubs exist only so Pester can mock them.')]
param()

# Pester tests for Invoke-CIPPBecRelease: which containment it reverses, how prior mailbox state
# limits what it turns back on, and the release entry it records on the case.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { throw 'no table in tests' }
    function Get-CIPPBecReport { param($TenantFilter, $CaseId, [switch]$IncludeResults) }
    function Set-CIPPBecReport { param($TenantFilter, $CaseId, $Properties) }
    function Set-CIPPSignInState { param($UserID, $AccountEnabled, $TenantFilter, $APIName, $Headers) }
    function Set-CIPPDeviceState { param($Action, $DeviceID, $TenantFilter, $Headers, $APIName) }
    function Remove-CIPPBecTargetedCAPolicy { param($TenantFilter, $PolicyId, $UserId, $Headers, $APIName) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Anchor) }
    function Write-LogMessage { param($message, $tenant, $API, $headers, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecContainmentActions.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Invoke-CIPPBecRelease.ps1')

    function New-Row { param($Action, $Target = 'victim@contoso.com', $State = 'success') [pscustomobject]@{ Action = $Action; Target = $Target; state = $State; resultText = 'done' } }
    # A case as Get-CIPPBecReport returns it: history entries and the snapshot come back as objects
    function New-Case {
        param([object[]]$Containment, $MailboxState)
        [pscustomobject]@{
            UserPrincipalName = 'victim@contoso.com'
            UserId            = 'u1'
            Containment       = $Containment
            Results           = [pscustomobject]@{ MailboxState = $MailboxState }
        }
    }
}

Describe 'Invoke-CIPPBecRelease' {
    BeforeEach {
        Mock Set-CIPPBecReport { }
        Mock Set-CIPPSignInState { 'Successfully set account enabled state to True for victim@contoso.com' }
        Mock Set-CIPPDeviceState { 'Enabled device' }
        Mock Remove-CIPPBecTargetedCAPolicy { 'Removed BEC containment Conditional Access policy pol-1' }
        Mock New-ExoRequest { }
        Mock Write-LogMessage { }
    }

    It 'reverses only lockouts that succeeded and lists cleanup and one-way actions instead' {
        Mock Get-CIPPBecReport {
            New-Case -Containment @([pscustomobject]@{
                    Actions = @('ResetPassword', 'DisableAccount', 'DisableInboxRules', 'BlockProtocols')
                    Results = @((New-Row 'ResetPassword'), (New-Row 'DisableAccount'), (New-Row 'DisableInboxRules'), (New-Row 'BlockProtocols' -State 'error'))
                })
        }

        $Rows = Invoke-CIPPBecRelease -TenantFilter 'contoso.com' -CaseId 'BEC-1'

        Should -Invoke Set-CIPPSignInState -Times 1 -Exactly -ParameterFilter { $AccountEnabled -eq $true -and $UserID -eq 'victim@contoso.com' }
        Should -Invoke New-ExoRequest -Times 0 -Exactly
        ($Rows | Where-Object Action -EQ 'DisableInboxRules').resultText | Should -Match '^Left in place'
        ($Rows | Where-Object Action -EQ 'ResetPassword').resultText | Should -Match '^Not reversed'
        $Rows.Action | Should -Not -Contain 'BlockProtocols'
    }

    It 'restores the protocol settings containment recorded, leaving an already-off protocol off' {
        Mock Get-CIPPBecReport {
            New-Case -Containment @([pscustomobject]@{
                    Actions = @('BlockProtocols')
                    Results = @(New-Row 'BlockProtocols')
                    Before  = [pscustomobject]@{ BlockProtocols = [pscustomobject]@{ EWSEnabled = $true; IMAPEnabled = $false; SmtpClientAuthenticationDisabled = $null } }
                }) -MailboxState ([pscustomobject]@{ IMAPEnabled = $true })
        }

        $null = Invoke-CIPPBecRelease -TenantFilter 'contoso.com' -CaseId 'BEC-1'

        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Set-CASMailbox' -and $cmdParams.EWSEnabled -eq $true -and $cmdParams.IMAPEnabled -eq $false -and
            $cmdParams.ContainsKey('SmtpClientAuthenticationDisabled') -and $null -eq $cmdParams.SmtpClientAuthenticationDisabled -and
            -not $cmdParams.ContainsKey('POPEnabled')
        }
    }

    It 'falls back to the investigation snapshot when containment recorded no prior settings' {
        Mock Get-CIPPBecReport {
            New-Case -Containment @([pscustomobject]@{ Actions = @('BlockProtocols'); Results = @(New-Row 'BlockProtocols') }) -MailboxState ([pscustomobject]@{ EWSEnabled = $true; POPEnabled = $false; PrimarySmtpAddress = 'victim@contoso.com' })
        }

        $null = Invoke-CIPPBecRelease -TenantFilter 'contoso.com' -CaseId 'BEC-1'

        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdParams.EWSEnabled -eq $true -and $cmdParams.POPEnabled -eq $false -and -not $cmdParams.ContainsKey('PrimarySmtpAddress')
        }
    }

    It 'unblocks only the devices containment added to the block list' {
        Mock Get-CIPPBecReport {
            New-Case -Containment @([pscustomobject]@{
                    Actions = @('BlockMobileDevices')
                    Results = @((New-Row 'BlockMobileDevices' -Target 'dev-1'), (New-Row 'BlockMobileDevices' -Target 'dev-2'))
                    Before  = [pscustomobject]@{ BlockMobileDevices = [pscustomobject]@{ ActiveSyncBlockedDeviceIDs = @('dev-2') } }
                })
        }

        $Rows = Invoke-CIPPBecRelease -TenantFilter 'contoso.com' -CaseId 'BEC-1'

        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { (@($cmdParams.ActiveSyncBlockedDeviceIDs.remove) -join ',') -eq 'dev-1' }
        ($Rows | Where-Object Target -EQ 'dev-2').resultText | Should -Match 'before containment'
    }

    It 're-enables disabled registered devices and removes the targeted CA policy' {
        Mock Get-CIPPBecReport {
            New-Case -Containment @([pscustomobject]@{
                    Actions = @('DisableRegisteredDevices', 'TargetedCAPolicy')
                    Results = @((New-Row 'DisableRegisteredDevices' -Target 'device-1'), (New-Row 'TargetedCAPolicy'))
                })
        }

        $null = Invoke-CIPPBecRelease -TenantFilter 'contoso.com' -CaseId 'BEC-1'

        Should -Invoke Set-CIPPDeviceState -Times 1 -Exactly -ParameterFilter { $Action -eq 'Enable' -and $DeviceID -eq 'device-1' }
        Should -Invoke Remove-CIPPBecTargetedCAPolicy -Times 1 -Exactly -ParameterFilter { $UserId -eq 'u1' }
    }

    It 'warns instead of failing when the re-enabled account is directory-synced' {
        Mock Get-CIPPBecReport { New-Case -Containment @([pscustomobject]@{ Actions = @('DisableAccount'); Results = @(New-Row 'DisableAccount') }) }
        Mock Set-CIPPSignInState { throw 'Failed to set sign-in state. Error: WARNING: User victim@contoso.com is AD Sync enabled.' }

        $Rows = Invoke-CIPPBecRelease -TenantFilter 'contoso.com' -CaseId 'BEC-1'

        ($Rows | Where-Object Action -EQ 'DisableAccount').state | Should -Be 'warning'
    }

    It 'ignores containment from before the last release' {
        Mock Get-CIPPBecReport {
            New-Case -Containment @(
                [pscustomobject]@{ Actions = @('DisableAccount'); Results = @(New-Row 'DisableAccount') }
                [pscustomobject]@{ Kind = 'Release'; Actions = @('DisableAccount'); Results = @(New-Row 'DisableAccount') }
            )
        }

        { Invoke-CIPPBecRelease -TenantFilter 'contoso.com' -CaseId 'BEC-1' } | Should -Throw '*no containment in force*'
        Should -Invoke Set-CIPPSignInState -Times 0 -Exactly
    }

    It 'refuses an action the case cannot release' {
        Mock Get-CIPPBecReport { New-Case -Containment @([pscustomobject]@{ Actions = @('DisableAccount', 'ResetPassword'); Results = @((New-Row 'DisableAccount'), (New-Row 'ResetPassword')) }) }

        { Invoke-CIPPBecRelease -TenantFilter 'contoso.com' -CaseId 'BEC-1' -Actions @('ResetPassword') } | Should -Throw '*ResetPassword*'
        Should -Invoke Set-CIPPSignInState -Times 0 -Exactly
    }

    It 'appends the release to the case history' {
        Mock Get-CIPPBecReport { New-Case -Containment @([pscustomobject]@{ Actions = @('DisableAccount'); Results = @(New-Row 'DisableAccount') }) }

        $null = Invoke-CIPPBecRelease -TenantFilter 'contoso.com' -CaseId 'BEC-1' -Headers 'Alert Engine'

        Should -Invoke Set-CIPPBecReport -Times 1 -Exactly -ParameterFilter {
            $Entries = @($Properties.Containment)
            $Entries.Count -eq 2 -and $Entries[1].Kind -eq 'Release' -and $Entries[1].By -eq 'Alert Engine' -and (@($Entries[1].Actions) -join ',') -eq 'DisableAccount'
        }
    }
}
