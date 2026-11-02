# CreateSharedMailbox is an instance standard: one configured address, graded on existence
# only. These tests pin the two decisions that fail silently - the case-insensitive match
# against the cached primary address OR UPN (a case mismatch would be permanent drift that
# New-Mailbox can never clear), and the executor's live guard that stops a stale Mailboxes
# cache from re-creating a mailbox that already exists - plus the create -> wait 3s ->
# Graph disable sequence itself.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'

    function New-CIPPDbRequest { param($TenantFilter, $Type) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $UseSystemMailbox) }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $body) }
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = "$($Exception.Exception.Message)" } }

    . (Join-Path $Baselines 'PrepareHooks/Get-CIPPBaselineCreateSharedMailboxState.ps1')
    . (Join-Path $Baselines 'Executors/Invoke-CIPPBaselineCreateSharedMailbox.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    function ConvertTo-Cached { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { $InputObject | ConvertTo-Json -Depth 10 | ConvertFrom-Json } }
    $script:Mailboxes = @(
        [PSCustomObject]@{ primarySmtpAddress = 'Info@contoso.com'; UPN = 'info@contoso.com'; displayName = 'Info'; recipientTypeDetails = 'SharedMailbox'; AccountDisabled = $true; ExternalDirectoryObjectId = 'obj-info' }
        [PSCustomObject]@{ primarySmtpAddress = 'alice@contoso.com'; UPN = 'alice@contoso.com'; displayName = 'Alice'; recipientTypeDetails = 'UserMailbox'; AccountDisabled = $false; ExternalDirectoryObjectId = 'obj-alice' }
        [PSCustomObject]@{ primarySmtpAddress = 'sales@contoso.com'; UPN = 'sales@contoso.onmicrosoft.com'; displayName = 'Sales'; recipientTypeDetails = 'SharedMailbox'; AccountDisabled = $false; ExternalDirectoryObjectId = 'obj-sales' }
    ) | ConvertTo-Cached
    function Invoke-Hook {
        param($Variables)
        Get-CIPPBaselineCreateSharedMailboxState -Item ([PSCustomObject]@{ Variables = $Variables }) -TenantFilter $script:Tenant
    }
}

Describe 'Get-CIPPBaselineCreateSharedMailboxState' {
    BeforeEach { Mock New-CIPPDbRequest { $script:Mailboxes } }

    It 'drifts when no mailbox carries the configured address' {
        $Prepared = Invoke-Hook ([PSCustomObject]@{ primarySmtpAddress = 'support@contoso.com'; displayName = 'Support' })
        $Prepared.Expected.exists | Should -BeTrue
        $Prepared.Current.exists | Should -BeFalse
        $Prepared.Current.primarySmtpAddress | Should -Be 'support@contoso.com'
    }

    It 'matches the primary address case-insensitively and carries the mailbox facts ungraded' {
        $Prepared = Invoke-Hook ([PSCustomObject]@{ primarySmtpAddress = 'INFO@contoso.com'; displayName = 'Info' })
        $Prepared.Current.exists | Should -BeTrue
        $Prepared.Current.displayName | Should -Be 'Info'
        $Prepared.Current.recipientTypeDetails | Should -Be 'SharedMailbox'
        $Prepared.Current.accountDisabled | Should -BeTrue
        $Prepared.Current.externalDirectoryObjectId | Should -Be 'obj-info'
        @($Prepared.Expected.PSObject.Properties.Name) | Should -Be @('exists')
    }

    It 'also matches on the UPN so a mailbox addressed under the onmicrosoft domain is found' {
        $Prepared = Invoke-Hook ([PSCustomObject]@{ primarySmtpAddress = 'sales@contoso.onmicrosoft.com'; displayName = 'Sales' })
        $Prepared.Current.exists | Should -BeTrue
    }

    It 'grades existence only - a user mailbox occupying the address is compliant, not drift' {
        $Prepared = Invoke-Hook ([PSCustomObject]@{ primarySmtpAddress = 'alice@contoso.com'; displayName = 'Alice' })
        $Prepared.Current.exists | Should -BeTrue
        $Prepared.Current.recipientTypeDetails | Should -Be 'UserMailbox'
    }

    It 'accepts the {label, value} wrapper and surrounding whitespace on the address' {
        $Prepared = Invoke-Hook ([PSCustomObject]@{ primarySmtpAddress = [PSCustomObject]@{ label = ' info@contoso.com '; value = ' info@contoso.com ' }; displayName = 'Info' })
        $Prepared.Current.exists | Should -BeTrue
    }

    It 'returns a null Current on an empty mailbox cache so the engine collects instead of grading' {
        Mock New-CIPPDbRequest { @() }
        $Prepared = Invoke-Hook ([PSCustomObject]@{ primarySmtpAddress = 'info@contoso.com'; displayName = 'Info' })
        $Prepared.Current | Should -BeNullOrEmpty
    }

    It 'returns No Data with a reason for an address that is not an email address' {
        $Prepared = Invoke-Hook ([PSCustomObject]@{ primarySmtpAddress = 'not an address'; displayName = 'Info' })
        $Prepared.Current | Should -BeNullOrEmpty
        $Prepared.NoDataReason | Should -Match 'not a valid email address'
    }

    It 'returns a null Current when the address is blank' {
        $Prepared = Invoke-Hook ([PSCustomObject]@{ primarySmtpAddress = ''; displayName = 'Info' })
        $Prepared.Current | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-CIPPBaselineCreateSharedMailbox' {
    BeforeEach {
        Mock Start-Sleep {}
        Mock New-GraphPostRequest { $null }
        Mock New-ExoRequest {
            if ($cmdlet -eq 'Get-Mailbox') { throw "The operation couldn't be performed because object '$($cmdParams.Identity)' couldn't be found." }
            if ($cmdlet -eq 'New-Mailbox') { [PSCustomObject]@{ ExternalDirectoryObjectId = 'new-obj-id'; Guid = 'mbx-guid' } }
        }
        $script:Remediate = [PSCustomObject]@{ primarySmtpAddress = 'support@contoso.com'; displayName = 'Support Desk' }
        $script:Missing = [PSCustomObject]@{ exists = $false; primarySmtpAddress = 'support@contoso.com' }
    }

    It 'creates the shared mailbox, waits three seconds, then disables the account through Graph' {
        $Output = Invoke-CIPPBaselineCreateSharedMailbox -Remediate $script:Remediate -TenantFilter $script:Tenant -Current $script:Missing
        $Output | Should -BeNullOrEmpty
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'New-Mailbox' -and $cmdParams.Shared -eq $true -and $cmdParams.displayName -eq 'Support Desk' -and
            $cmdParams.primarySMTPAddress -eq 'support@contoso.com' -and $cmdParams.name -eq 'support' -and $tenantid -eq $script:Tenant
        }
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 3 }
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $type -eq 'PATCH' -and $uri -eq 'https://graph.microsoft.com/v1.0/users/new-obj-id' -and
            ($body | ConvertFrom-Json).accountEnabled -eq $false -and $tenantid -eq $script:Tenant
        }
    }

    It 'skips the create and reports Changed=$false when the mailbox already exists live (stale cache)' {
        Mock New-ExoRequest {
            if ($cmdlet -eq 'Get-Mailbox') { [PSCustomObject]@{ Identity = 'support'; PrimarySmtpAddress = 'support@contoso.com' } }
            if ($cmdlet -eq 'New-Mailbox') { throw 'New-Mailbox must not run for an existing address' }
        }
        $Output = Invoke-CIPPBaselineCreateSharedMailbox -Remediate $script:Remediate -TenantFilter $script:Tenant -Current $script:Missing
        $Output.Changed | Should -BeFalse
        Should -Invoke New-ExoRequest -Times 0 -ParameterFilter { $cmdlet -eq 'New-Mailbox' }
        Should -Invoke New-GraphPostRequest -Times 0
        Should -Invoke Start-Sleep -Times 0
    }

    It 'falls back to the address as the Graph user key when the create response has no object id' {
        Mock New-ExoRequest {
            if ($cmdlet -eq 'Get-Mailbox') { throw 'not found' }
            if ($cmdlet -eq 'New-Mailbox') { [PSCustomObject]@{ Guid = 'mbx-guid' } }
        }
        Invoke-CIPPBaselineCreateSharedMailbox -Remediate $script:Remediate -TenantFilter $script:Tenant -Current $script:Missing
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -eq 'https://graph.microsoft.com/v1.0/users/support@contoso.com' }
    }

    It 'unwraps {label, value} option objects on both variables' {
        $Wrapped = [PSCustomObject]@{
            primarySmtpAddress = [PSCustomObject]@{ label = 'support@contoso.com'; value = 'support@contoso.com' }
            displayName        = [PSCustomObject]@{ label = 'Support Desk'; value = 'Support Desk' }
        }
        Invoke-CIPPBaselineCreateSharedMailbox -Remediate $Wrapped -TenantFilter $script:Tenant -Current $script:Missing
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'New-Mailbox' -and $cmdParams.displayName -eq 'Support Desk' -and $cmdParams.primarySMTPAddress -eq 'support@contoso.com' }
    }

    It 'throws when the sign-in block fails after the create, naming the address' {
        Mock New-GraphPostRequest { throw 'Request_ResourceNotFound' }
        { Invoke-CIPPBaselineCreateSharedMailbox -Remediate $script:Remediate -TenantFilter $script:Tenant -Current $script:Missing } |
            Should -Throw -ExpectedMessage "*support@contoso.com*failed to block sign-in*"
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'New-Mailbox' }
    }

    It 'refuses to run without a display name or with an invalid address, before touching Exchange' {
        { Invoke-CIPPBaselineCreateSharedMailbox -Remediate ([PSCustomObject]@{ primarySmtpAddress = 'support@contoso.com'; displayName = '' }) -TenantFilter $script:Tenant -Current $script:Missing } | Should -Throw
        { Invoke-CIPPBaselineCreateSharedMailbox -Remediate ([PSCustomObject]@{ primarySmtpAddress = 'support'; displayName = 'Support' }) -TenantFilter $script:Tenant -Current $script:Missing } | Should -Throw -ExpectedMessage '*not a valid email address*'
        Should -Invoke New-ExoRequest -Times 0
    }
}
