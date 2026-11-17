# Restoring users with overwrite rewrites existing users from the backup; a restore queued without
# Identity.PrivilegedUser.ReadWrite must leave privileged users alone and still restore everyone else.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'New-CIPPRestoreTask.ps1' -File | Select-Object -First 1 -ExpandProperty FullName

    function Get-CIPPBackup { param($Type, $Name) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $type) }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Get-NormalizedError { param($Message) $Message }
    function New-passwordString { 'P@ss' }
    function New-PwPushLink { param($Payload) }
    function Assert-CippPrivilegedUserAccess { param($TenantFilter, $UserId, [switch]$PassThru) }
    . $FunctionPath

    function Invoke-UserRestore([bool]$Overwrite) {
        New-CIPPRestoreTask -Task 'users' -TenantFilter 'contoso.com' -backup 'b' -overwrite $Overwrite -APINAME 'Restore' -Headers @{}
    }
}

Describe 'New-CIPPRestoreTask users and privileged users' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock New-GraphPOSTRequest { }
        Mock Get-CIPPBackup {
            [pscustomobject]@{ users = @(
                    [pscustomobject]@{ id = 'admin-id'; userPrincipalName = 'admin@contoso.com'; accountEnabled = $true }
                    [pscustomobject]@{ id = 'user-id'; userPrincipalName = 'user@contoso.com'; accountEnabled = $true }
                    [pscustomobject]@{ id = 'new-id'; userPrincipalName = 'new@contoso.com'; accountEnabled = $true }
                ) }
        }
        Mock New-GraphGetRequest { @([pscustomobject]@{ id = 'admin-id'; userPrincipalName = 'admin@contoso.com' }, [pscustomobject]@{ id = 'user-id'; userPrincipalName = 'user@contoso.com' }) }
        Mock Assert-CippPrivilegedUserAccess { @($UserId).Where({ $_ -eq 'admin-id' }) }
    }

    It 'leaves a privileged user as it is and restores the others' {
        $Result = Invoke-UserRestore -Overwrite $true
        $Result | Should -Contain 'Skipped admin@contoso.com: they hold a privileged admin role. Managing privileged users needs the Identity.PrivilegedUser.ReadWrite permission.'
        Should -Invoke Assert-CippPrivilegedUserAccess -Times 1 -Exactly -ParameterFilter { (@($UserId) -join ',') -eq 'admin-id,user-id' -and $PassThru }
        Should -Invoke New-GraphPOSTRequest -Times 0 -ParameterFilter { $uri -like '*/users/admin-id' }
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/users/user-id' -and $type -eq 'PATCH' }
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'POST' }
    }

    It 'restores no users when it cannot tell who is privileged' {
        Mock Assert-CippPrivilegedUserAccess { throw 'Could not read the active role assignments' }
        $Result = Invoke-UserRestore -Overwrite $true
        $Result | Should -Contain 'Users were not restored: Could not read the active role assignments'
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'does not check when nothing existing is overwritten' {
        $null = Invoke-UserRestore -Overwrite $false
        Should -Invoke Assert-CippPrivilegedUserAccess -Times 0
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'POST' }
    }
}
