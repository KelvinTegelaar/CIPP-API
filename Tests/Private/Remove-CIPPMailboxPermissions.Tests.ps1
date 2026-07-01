# Pester tests for Remove-CIPPMailboxPermissions
# Covers the per-level single-mailbox removal branches (SendOnBehalf -> Set-Mailbox + GrantSendonBehalfTo,
# SendAs -> Remove-RecipientPermission, FullAccess -> Remove-MailboxPermission), cache-sync gating,
# the "already removed" message selection, the -UseCache report-driven path, and the error path.
#
# NOTE: the 'AllUsers' branch uses ForEach-Object -Parallel, which runs each iteration in a separate
# runspace that re-imports the real CIPPCore/AzBobbyTables modules. Pester mocks live in the test
# runspace and cannot cross that boundary, so that branch is intentionally NOT unit-tested here.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Remove-CIPPMailboxPermissions.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Remove-CIPPMailboxPermissions.ps1 under Modules/' }

    function New-ExoRequest { param($Anchor, $tenantid, $cmdlet, $cmdParams, $Select) }
    function Get-CippException { param($Exception) }
    function Get-CIPPMailboxPermissionReport { param($TenantFilter, [switch]$ByUser) }
    function Sync-CIPPMailboxPermissionCache { param($TenantFilter, $MailboxIdentity, $User, $PermissionType, $Action) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }

    . $FunctionPath
}

Describe 'Remove-CIPPMailboxPermissions' {
    BeforeEach {
        # A successful EXO removal returns a truthy response that does NOT contain an error substring.
        # (The branches use `$result -notlike '*error*'`; note that with a $null response,
        #  $null -notlike '<pattern>' is $false, which would route to the "already removed" message.)
        Mock -CommandName New-ExoRequest -MockWith { 'OK' }
        Mock -CommandName Get-CippException -MockWith { [pscustomobject]@{ NormalizedError = 'boom' } }
        Mock -CommandName Get-CIPPMailboxPermissionReport -MockWith { }
        Mock -CommandName Sync-CIPPMailboxPermissionCache -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }
    }

    Context 'Single-mailbox removal branches' {
        It 'removes SendOnBehalf via Set-Mailbox with a GrantSendonBehalfTo remove hashtable' {
            $result = Remove-CIPPMailboxPermissions -userid 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -TenantFilter 'contoso.com' -PermissionsLevel @('SendOnBehalf')

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdlet -eq 'Set-Mailbox' -and
                $cmdParams.GrantSendonBehalfTo.remove -eq 'user@contoso.com' -and
                $cmdParams.GrantSendonBehalfTo['@odata.type'] -eq '#Exchange.GenericHashTable'
            }
            $result | Should -Match "Removed SendOnBehalf permissions for user@contoso.com from shared@contoso.com's mailbox\."
        }

        It 'removes SendAs via Remove-RecipientPermission and syncs the cache' {
            $result = Remove-CIPPMailboxPermissions -userid 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -TenantFilter 'contoso.com' -PermissionsLevel @('SendAs')

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdlet -eq 'Remove-RecipientPermission' -and $cmdParams.Trustee -eq 'user@contoso.com'
            }
            Should -Invoke Sync-CIPPMailboxPermissionCache -Times 1 -Exactly -ParameterFilter {
                $PermissionType -eq 'SendAs' -and $Action -eq 'Remove'
            }
            $result | Should -Match "Removed SendAs permissions for user@contoso.com from shared@contoso.com's mailbox\."
        }

        It 'reports SendAs as already-removed when EXO says the ACE is not present' {
            Mock -CommandName New-ExoRequest -MockWith { "can't remove the ACL because the ACE isn't present" }

            $result = Remove-CIPPMailboxPermissions -userid 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -TenantFilter 'contoso.com' -PermissionsLevel @('SendAs')

            # cache is still synced regardless of whether the permission existed
            Should -Invoke Sync-CIPPMailboxPermissionCache -Times 1 -Exactly -ParameterFilter { $PermissionType -eq 'SendAs' }
            $result | Should -Match "were already removed or don't exist"
        }

        It 'removes FullAccess via Remove-MailboxPermission and syncs the cache' {
            $result = Remove-CIPPMailboxPermissions -userid 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -TenantFilter 'contoso.com' -PermissionsLevel @('FullAccess')

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdlet -eq 'Remove-MailboxPermission' -and
                $cmdParams.user -eq 'user@contoso.com' -and
                $cmdParams.accessRights -contains 'FullAccess'
            }
            Should -Invoke Sync-CIPPMailboxPermissionCache -Times 1 -Exactly -ParameterFilter { $PermissionType -eq 'FullAccess' }
            $result | Should -Match "Removed FullAccess permissions for user@contoso.com from shared@contoso.com's mailbox\."
        }

        It 'reports FullAccess as already-removed when EXO says the ACE does not exist' {
            Mock -CommandName New-ExoRequest -MockWith { "can't remove because the ACE doesn't exist on the object." }

            $result = Remove-CIPPMailboxPermissions -userid 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -TenantFilter 'contoso.com' -PermissionsLevel @('FullAccess')

            $result | Should -Match "were already removed or don't exist"
        }

        It 'processes multiple permission levels in one call' {
            $result = Remove-CIPPMailboxPermissions -userid 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -TenantFilter 'contoso.com' -PermissionsLevel @('FullAccess', 'SendAs', 'SendOnBehalf')

            Should -Invoke New-ExoRequest -Times 3 -Exactly
            $result.Count | Should -Be 3
        }
    }

    Context '-UseCache path' {
        It 'removes every cached permission for the user via recursion and returns per-mailbox results' {
            Mock -CommandName Get-CIPPMailboxPermissionReport -MockWith {
                [pscustomobject]@{
                    User        = 'user@contoso.com'
                    MailboxCount = 2
                    Permissions = @(
                        [pscustomobject]@{ MailboxUPN = 'sharedA@contoso.com'; AccessRights = 'FullAccess' }
                        [pscustomobject]@{ MailboxUPN = 'sharedB@contoso.com'; AccessRights = 'SendAs' }
                    )
                }
            }

            $result = Remove-CIPPMailboxPermissions -AccessUser 'user@contoso.com' -TenantFilter 'contoso.com' -UseCache

            Should -Invoke Get-CIPPMailboxPermissionReport -Times 1 -Exactly
            # one EXO call per recursive removal (FullAccess + SendAs)
            Should -Invoke New-ExoRequest -Times 2 -Exactly
            $result.Count | Should -Be 2
        }

        It 'returns an informational message when no cached permissions exist' {
            Mock -CommandName Get-CIPPMailboxPermissionReport -MockWith { }

            $result = Remove-CIPPMailboxPermissions -AccessUser 'user@contoso.com' -TenantFilter 'contoso.com' -UseCache

            Should -Invoke New-ExoRequest -Times 0 -Exactly
            $result | Should -Be 'No mailbox permissions found for user@contoso.com in cached data'
        }
    }

    Context 'Error path' {
        It 'returns a failure string and logs an error when New-ExoRequest throws' {
            Mock -CommandName New-ExoRequest -MockWith { throw 'EXO down' }

            $result = Remove-CIPPMailboxPermissions -userid 'shared@contoso.com' -AccessUser 'user@contoso.com' `
                -TenantFilter 'contoso.com' -PermissionsLevel @('FullAccess')

            $result | Should -Be 'Could not remove mailbox permissions for shared@contoso.com. Error: boom'
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Error' }
        }
    }
}
