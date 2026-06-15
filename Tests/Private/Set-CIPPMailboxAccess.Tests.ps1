# Pester tests for Set-CIPPMailboxAccess
# Set-CIPPMailboxAccess now delegates each grant to Set-CIPPMailboxPermission (FullAccess / Add), so
# these tests cover the per-user fan-out, extraction of frontend objects with a .value property,
# AutoMap pass-through, and that one user's failure does not stop the rest (the delegate returns an
# error string rather than throwing). The EXO cmdlet mapping itself is covered by
# Set-CIPPMailboxPermission.Tests.ps1.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Set-CIPPMailboxAccess.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Set-CIPPMailboxAccess.ps1 under Modules/' }

    function Set-CIPPMailboxPermission { param($UserId, $AccessUser, $PermissionLevel, $Action, $AutoMap, $TenantFilter, $APIName, $Headers) }

    . $FunctionPath
}

Describe 'Set-CIPPMailboxAccess' {
    BeforeEach {
        Mock -CommandName Set-CIPPMailboxPermission -MockWith { "Granted $AccessUser FullAccess to $UserId with automapping $AutoMap" }
    }

    It 'delegates a single user to Set-CIPPMailboxPermission as a FullAccess Add' {
        $result = Set-CIPPMailboxAccess -userid 'shared@contoso.com' -AccessUser 'user@contoso.com' `
            -Automap $true -TenantFilter 'contoso.com' -AccessRights @('FullAccess')

        Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly -ParameterFilter {
            $UserId -eq 'shared@contoso.com' -and
            $AccessUser -eq 'user@contoso.com' -and
            $PermissionLevel -eq 'FullAccess' -and
            $Action -eq 'Add' -and
            $AutoMap -eq $true -and
            $TenantFilter -eq 'contoso.com'
        }
        $result | Should -Contain 'Granted user@contoso.com FullAccess to shared@contoso.com with automapping True'
    }

    It 'processes an array of users, one delegate call per user' {
        $result = Set-CIPPMailboxAccess -userid 'shared@contoso.com' -AccessUser @('a@contoso.com', 'b@contoso.com') `
            -Automap $true -TenantFilter 'contoso.com' -AccessRights @('FullAccess')

        Should -Invoke Set-CIPPMailboxPermission -Times 2 -Exactly
        $result.Count | Should -Be 2
    }

    It 'extracts the .value property from frontend objects' {
        $accessUsers = @([pscustomobject]@{ value = 'picked@contoso.com'; label = 'Picked User' })

        Set-CIPPMailboxAccess -userid 'shared@contoso.com' -AccessUser $accessUsers `
            -Automap $true -TenantFilter 'contoso.com' -AccessRights @('FullAccess')

        Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly -ParameterFilter { $AccessUser -eq 'picked@contoso.com' }
    }

    It 'passes AutoMap through to the delegate when disabled' {
        Set-CIPPMailboxAccess -userid 'shared@contoso.com' -AccessUser 'user@contoso.com' `
            -Automap $false -TenantFilter 'contoso.com' -AccessRights @('FullAccess')

        Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly -ParameterFilter { $AutoMap -eq $false }
    }

    It 'continues to the next user when one user returns a failure string' {
        Mock -CommandName Set-CIPPMailboxPermission -MockWith {
            if ($AccessUser -eq 'bad@contoso.com') {
                'Failed to Add FullAccess for bad@contoso.com on shared@contoso.com: boom'
            } else {
                "Granted $AccessUser FullAccess to shared@contoso.com with automapping True"
            }
        }

        $result = Set-CIPPMailboxAccess -userid 'shared@contoso.com' -AccessUser @('bad@contoso.com', 'good@contoso.com') `
            -Automap $true -TenantFilter 'contoso.com' -AccessRights @('FullAccess')

        Should -Invoke Set-CIPPMailboxPermission -Times 2 -Exactly
        ($result -join "`n") | Should -Match 'Failed to Add FullAccess for bad@contoso.com on shared@contoso.com: boom'
        ($result -join "`n") | Should -Match 'Granted good@contoso.com FullAccess to shared@contoso.com'
    }
}
