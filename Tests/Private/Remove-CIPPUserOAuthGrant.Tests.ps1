BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $AsApp, $body) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Remove-CIPPUserOAuthGrant.ps1')
}

Describe 'Remove-CIPPUserOAuthGrant' {
    BeforeEach {
        Mock New-GraphPOSTRequest { }
        Mock Write-LogMessage { }
    }

    It 'deletes each consent grant and app-role assignment at its own Graph URI and returns a success row per id' {
        $Rows = Remove-CIPPUserOAuthGrant -TenantFilter 'contoso.com' -UserId 'user-1' -GrantIds @('g1', 'g2') -AppRoleAssignmentIds @('a1') -Headers @{ 'x-ms-client-principal' = 'test' }

        Should -Invoke New-GraphPOSTRequest -Exactly -Times 3 -ParameterFilter { $type -eq 'DELETE' -and $AsApp -eq $true -and $tenantid -eq 'contoso.com' }
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { $uri -eq 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants/g1' }
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { $uri -eq 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants/g2' }
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { $uri -eq 'https://graph.microsoft.com/v1.0/users/user-1/appRoleAssignments/a1' }
        Should -Invoke Write-LogMessage -Exactly -Times 3 -ParameterFilter { $Sev -eq 'Info' -and $API -eq 'BECRemediate' -and $tenant -eq 'contoso.com' -and $headers.'x-ms-client-principal' -eq 'test' }
        $Rows.Count | Should -Be 3
        $Rows.Target | Should -Be @('g1', 'g2', 'a1')
        $Rows.state | Should -Be @('success', 'success', 'success')
        $Rows[0].resultText | Should -Be 'Deleted consent grant g1'
        $Rows[2].resultText | Should -Be 'Deleted app-role assignment a1'
        $Rows[0].PSObject.Properties.Name | Should -Be @('Target', 'state', 'resultText')
    }

    It 'refuses an app-role assignment without the user object id and never calls Graph for it, while still deleting the grants' {
        $Rows = Remove-CIPPUserOAuthGrant -TenantFilter 'contoso.com' -GrantIds @('g1') -AppRoleAssignmentIds @('a1')

        Should -Invoke New-GraphPOSTRequest -Exactly -Times 1 -ParameterFilter { $uri -like '*/oauth2PermissionGrants/g1' }
        Should -Invoke New-GraphPOSTRequest -Times 0 -ParameterFilter { $uri -like '*appRoleAssignments*' }
        $Rows.Count | Should -Be 2
        ($Rows | Where-Object { $_.Target -eq 'g1' }).state | Should -Be 'success'
        $Assignment = $Rows | Where-Object { $_.Target -eq 'a1' }
        $Assignment.state | Should -Be 'error'
        $Assignment.resultText | Should -Be 'The user object id is required to remove an app-role assignment'
        Should -Invoke Write-LogMessage -Exactly -Times 1 -Because 'the refused assignment is a validation result, not an audit event'
    }

    It 'turns a Graph failure into an error row and carries on with the next id' {
        Mock New-GraphPOSTRequest -ParameterFilter { $uri -like '*/oauth2PermissionGrants/g1' } { throw 'Insufficient privileges to complete the operation.' }
        $Rows = Remove-CIPPUserOAuthGrant -TenantFilter 'contoso.com' -UserId 'user-1' -GrantIds @('g1', 'g2') -AppRoleAssignmentIds @('a1')

        Should -Invoke New-GraphPOSTRequest -Exactly -Times 3
        $Rows.Count | Should -Be 3
        $Rows[0].state | Should -Be 'error'
        $Rows[0].resultText | Should -Be 'Failed to delete consent grant g1: Insufficient privileges to complete the operation.'
        $Rows[1].state | Should -Be 'success'
        $Rows[2].state | Should -Be 'success'
        Should -Invoke Write-LogMessage -Exactly -Times 1 -ParameterFilter { $Sev -eq 'Error' -and $null -ne $LogData -and $message -like 'Failed to delete consent grant g1*' }
        Should -Invoke Write-LogMessage -Exactly -Times 2 -ParameterFilter { $Sev -eq 'Info' }
    }

    It 'returns an empty array for empty input and ignores blank ids' {
        @(Remove-CIPPUserOAuthGrant -TenantFilter 'contoso.com' -UserId 'user-1').Count | Should -Be 0
        @(Remove-CIPPUserOAuthGrant -TenantFilter 'contoso.com' -UserId 'user-1' -GrantIds @('', $null) -AppRoleAssignmentIds @()).Count | Should -Be 0
        Should -Invoke New-GraphPOSTRequest -Times 0
        Should -Invoke Write-LogMessage -Times 0
    }

    It 'deletes nothing and returns no rows under -WhatIf' {
        $Rows = Remove-CIPPUserOAuthGrant -TenantFilter 'contoso.com' -UserId 'user-1' -GrantIds @('g1') -AppRoleAssignmentIds @('a1') -WhatIf
        @($Rows).Count | Should -Be 0
        Should -Invoke New-GraphPOSTRequest -Times 0
        Should -Invoke Write-LogMessage -Times 0
    }
}
