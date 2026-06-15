# Pester tests for Set-CIPPMailboxPermission
# Covers the permission-level -> EXO cmdlet/parameter mapping (via -AsCmdletObject, no execution),
# the execute path (New-ExoRequest + logging), cache-sync gating, and the error path.

BeforeAll {
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Set-CIPPMailboxPermission.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Set-CIPPMailboxPermission.ps1 under Modules/' }

    # Stub every CIPP helper the function calls so Pester's Mock has a command to replace.
    function New-ExoRequest { param($Anchor, $tenantid, $cmdlet, $cmdParams) }
    function Get-CippException { param($Exception) }
    function Sync-CIPPMailboxPermissionCache { param($TenantFilter, $MailboxIdentity, $User, $PermissionType, $Action) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }

    . $FunctionPath
}

Describe 'Set-CIPPMailboxPermission' {

    Context '-AsCmdletObject mapping matrix (no execution)' {

        It 'maps FullAccess Add to Add-MailboxPermission with automapping and InheritanceType' {
            $result = Set-CIPPMailboxPermission -UserId 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -PermissionLevel 'FullAccess' -Action 'Add' -AutoMap $true -TenantFilter 'contoso.com' -AsCmdletObject

            $result.CmdletName | Should -Be 'Add-MailboxPermission'
            $result.Parameters.Identity | Should -Be 'shared@contoso.com'
            $result.Parameters.user | Should -Be 'user@contoso.com'
            $result.Parameters.accessRights | Should -Be @('FullAccess')
            $result.Parameters.automapping | Should -BeTrue
            $result.Parameters.InheritanceType | Should -Be 'all'
            $result.Parameters.Confirm | Should -BeFalse
            $result.ExpectedResult | Should -Be 'Granted user@contoso.com FullAccess to shared@contoso.com with automapping True'
        }

        It 'passes automapping through as $false when AutoMap is disabled' {
            $result = Set-CIPPMailboxPermission -UserId 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -PermissionLevel 'FullAccess' -Action 'Add' -AutoMap $false -TenantFilter 'contoso.com' -AsCmdletObject

            $result.Parameters.automapping | Should -BeFalse
            $result.ExpectedResult | Should -Match 'automapping False'
        }

        It 'maps FullAccess Remove to Remove-MailboxPermission' {
            $result = Set-CIPPMailboxPermission -UserId 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -PermissionLevel 'FullAccess' -Action 'Remove' -TenantFilter 'contoso.com' -AsCmdletObject

            $result.CmdletName | Should -Be 'Remove-MailboxPermission'
            $result.Parameters.accessRights | Should -Be @('FullAccess')
            $result.Parameters.Keys | Should -Not -Contain 'automapping'
            $result.ExpectedResult | Should -Be 'Removed user@contoso.com FullAccess from shared@contoso.com'
        }

        It 'maps SendAs Add to Add-RecipientPermission with Trustee' {
            $result = Set-CIPPMailboxPermission -UserId 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -PermissionLevel 'SendAs' -Action 'Add' -TenantFilter 'contoso.com' -AsCmdletObject

            $result.CmdletName | Should -Be 'Add-RecipientPermission'
            $result.Parameters.Trustee | Should -Be 'user@contoso.com'
            $result.Parameters.accessRights | Should -Be @('SendAs')
            $result.ExpectedResult | Should -Be 'Granted user@contoso.com SendAs permissions to shared@contoso.com'
        }

        It 'maps SendAs Remove to Remove-RecipientPermission with Trustee' {
            $result = Set-CIPPMailboxPermission -UserId 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -PermissionLevel 'SendAs' -Action 'Remove' -TenantFilter 'contoso.com' -AsCmdletObject

            $result.CmdletName | Should -Be 'Remove-RecipientPermission'
            $result.Parameters.Trustee | Should -Be 'user@contoso.com'
            $result.ExpectedResult | Should -Be 'Removed user@contoso.com SendAs permissions from shared@contoso.com'
        }

        It 'maps SendOnBehalf Add to Set-Mailbox with GrantSendonBehalfTo add hashtable' {
            $result = Set-CIPPMailboxPermission -UserId 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -PermissionLevel 'SendOnBehalf' -Action 'Add' -TenantFilter 'contoso.com' -AsCmdletObject

            $result.CmdletName | Should -Be 'Set-Mailbox'
            $result.Parameters.GrantSendonBehalfTo['@odata.type'] | Should -Be '#Exchange.GenericHashTable'
            $result.Parameters.GrantSendonBehalfTo.add | Should -Be 'user@contoso.com'
            $result.Parameters.GrantSendonBehalfTo.Keys | Should -Not -Contain 'remove'
            $result.ExpectedResult | Should -Be 'Granted user@contoso.com SendOnBehalf permissions to shared@contoso.com'
        }

        It 'maps SendOnBehalf Remove to Set-Mailbox with GrantSendonBehalfTo remove hashtable' {
            $result = Set-CIPPMailboxPermission -UserId 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -PermissionLevel 'SendOnBehalf' -Action 'Remove' -TenantFilter 'contoso.com' -AsCmdletObject

            $result.CmdletName | Should -Be 'Set-Mailbox'
            $result.Parameters.GrantSendonBehalfTo.remove | Should -Be 'user@contoso.com'
            $result.Parameters.GrantSendonBehalfTo.Keys | Should -Not -Contain 'add'
            $result.ExpectedResult | Should -Be 'Removed user@contoso.com SendOnBehalf permissions from shared@contoso.com'
        }

        It 'maps default-level Remove (<Level>) to Remove-MailboxPermission with that access right' -ForEach @(
            @{ Level = 'ReadPermission' }
            @{ Level = 'ExternalAccount' }
            @{ Level = 'DeleteItem' }
            @{ Level = 'ChangePermission' }
            @{ Level = 'ChangeOwner' }
        ) {
            $result = Set-CIPPMailboxPermission -UserId 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -PermissionLevel $Level -Action 'Remove' -TenantFilter 'contoso.com' -AsCmdletObject

            $result.CmdletName | Should -Be 'Remove-MailboxPermission'
            $result.Parameters.accessRights | Should -Be @($Level)
            $result.ExpectedResult | Should -Be "Removed user@contoso.com $Level from shared@contoso.com"
        }

        It 'returns an unsupported-action string for default-level Add (<Level>)' -ForEach @(
            @{ Level = 'ReadPermission' }
            @{ Level = 'ExternalAccount' }
            @{ Level = 'DeleteItem' }
            @{ Level = 'ChangePermission' }
            @{ Level = 'ChangeOwner' }
        ) {
            $result = Set-CIPPMailboxPermission -UserId 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -PermissionLevel $Level -Action 'Add' -TenantFilter 'contoso.com' -AsCmdletObject

            $result | Should -Be "Add action is not supported for $Level"
        }
    }

    Context 'Execute path' {
        BeforeEach {
            Mock -CommandName New-ExoRequest -MockWith { }
            Mock -CommandName Sync-CIPPMailboxPermissionCache -MockWith { }
            Mock -CommandName Write-LogMessage -MockWith { }
            Mock -CommandName Get-CippException -MockWith { [pscustomobject]@{ NormalizedError = 'boom' } }
        }

        It 'invokes New-ExoRequest with the mapped cmdlet/params anchored on the mailbox and returns the result string' {
            $result = Set-CIPPMailboxPermission -UserId 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -PermissionLevel 'FullAccess' -Action 'Add' -TenantFilter 'contoso.com'

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdlet -eq 'Add-MailboxPermission' -and
                $Anchor -eq 'shared@contoso.com' -and
                $tenantid -eq 'contoso.com' -and
                $cmdParams.user -eq 'user@contoso.com'
            }
            $result | Should -Be 'Granted user@contoso.com FullAccess to shared@contoso.com with automapping True'
        }

        It 'logs an Info message on success' {
            Set-CIPPMailboxPermission -UserId 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -PermissionLevel 'SendAs' -Action 'Add' -TenantFilter 'contoso.com'

            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Info' }
        }

        It 'syncs the cache for cached permission types (<Level>)' -ForEach @(
            @{ Level = 'FullAccess' }
            @{ Level = 'SendAs' }
            @{ Level = 'SendOnBehalf' }
        ) {
            Set-CIPPMailboxPermission -UserId 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -PermissionLevel $Level -Action 'Add' -TenantFilter 'contoso.com'

            Should -Invoke Sync-CIPPMailboxPermissionCache -Times 1 -Exactly -ParameterFilter {
                $PermissionType -eq $Level -and $Action -eq 'Add'
            }
        }

        It 'does not sync the cache for non-cached permission types' {
            Set-CIPPMailboxPermission -UserId 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -PermissionLevel 'ReadPermission' -Action 'Remove' -TenantFilter 'contoso.com'

            Should -Invoke Sync-CIPPMailboxPermissionCache -Times 0 -Exactly
        }

        It 'returns a failure string and logs an error when New-ExoRequest throws' {
            Mock -CommandName New-ExoRequest -MockWith { throw 'EXO down' }

            $result = Set-CIPPMailboxPermission -UserId 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -PermissionLevel 'FullAccess' -Action 'Add' -TenantFilter 'contoso.com'

            $result | Should -Be 'Failed to Add FullAccess for user@contoso.com on shared@contoso.com: boom'
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Error' }
            Should -Invoke Sync-CIPPMailboxPermissionCache -Times 0 -Exactly
        }
    }
}
