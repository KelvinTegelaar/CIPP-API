# Pester tests for Set-CIPPMailboxAccess
# Covers granting Add-MailboxPermission for a single user and an array of users, extraction of
# frontend objects with a .value property, the automapping message wording, and per-user error handling.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Set-CIPPMailboxAccess.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Set-CIPPMailboxAccess.ps1 under Modules/' }

    function New-ExoRequest { param($Anchor, $tenantid, $cmdlet, $cmdParams) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }

    . $FunctionPath
}

Describe 'Set-CIPPMailboxAccess' {
    BeforeEach {
        Mock -CommandName New-ExoRequest -MockWith { }
        Mock -CommandName Get-CippException -MockWith { [pscustomobject]@{ NormalizedError = 'boom' } }
        Mock -CommandName Write-LogMessage -MockWith { }
    }

    It 'grants Add-MailboxPermission for a single user with the requested access rights' {
        $result = Set-CIPPMailboxAccess -userid 'shared@contoso.com' -AccessUser 'user@contoso.com' `
            -Automap $true -TenantFilter 'contoso.com' -AccessRights @('FullAccess')

        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Add-MailboxPermission' -and
            $Anchor -eq 'shared@contoso.com' -and
            $cmdParams.Identity -eq 'shared@contoso.com' -and
            $cmdParams.user -eq 'user@contoso.com' -and
            $cmdParams.AutoMapping -eq $true -and
            $cmdParams.accessRights -contains 'FullAccess' -and
            $cmdParams.InheritanceType -eq 'all'
        }
        $result | Should -Match 'Successfully added user@contoso.com to shared@contoso.com'
        $result | Should -Match 'with AutoMapping'
    }

    It 'processes an array of users, one Add-MailboxPermission per user' {
        $result = Set-CIPPMailboxAccess -userid 'shared@contoso.com' -AccessUser @('a@contoso.com', 'b@contoso.com') `
            -Automap $true -TenantFilter 'contoso.com' -AccessRights @('FullAccess')

        Should -Invoke New-ExoRequest -Times 2 -Exactly
        $result.Count | Should -Be 2
    }

    It 'extracts the .value property from frontend objects' {
        $accessUsers = @([pscustomobject]@{ value = 'picked@contoso.com'; label = 'Picked User' })

        Set-CIPPMailboxAccess -userid 'shared@contoso.com' -AccessUser $accessUsers `
            -Automap $true -TenantFilter 'contoso.com' -AccessRights @('FullAccess')

        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdParams.user -eq 'picked@contoso.com' }
    }

    It 'reports "without AutoMapping" when Automap is disabled' {
        $result = Set-CIPPMailboxAccess -userid 'shared@contoso.com' -AccessUser 'user@contoso.com' `
            -Automap $false -TenantFilter 'contoso.com' -AccessRights @('FullAccess')

        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdParams.AutoMapping -eq $false }
        $result | Should -Match 'without AutoMapping'
    }

    It 'records a failure message but continues to the next user when one user throws' {
        Mock -CommandName New-ExoRequest -MockWith {
            param($Anchor, $tenantid, $cmdlet, $cmdParams)
            if ($cmdParams.user -eq 'bad@contoso.com') { throw 'EXO down' }
        }

        $result = Set-CIPPMailboxAccess -userid 'shared@contoso.com' -AccessUser @('bad@contoso.com', 'good@contoso.com') `
            -Automap $true -TenantFilter 'contoso.com' -AccessRights @('FullAccess')

        Should -Invoke New-ExoRequest -Times 2 -Exactly
        ($result -join "`n") | Should -Match 'Failed to add mailbox permissions for bad@contoso.com on shared@contoso.com. Error: boom'
        ($result -join "`n") | Should -Match 'Successfully added good@contoso.com'
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Error' }
    }
}
