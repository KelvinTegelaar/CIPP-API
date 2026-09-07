BeforeAll {
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Remove-CIPPUserTeamsPhoneDIDs.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Remove-CIPPUserTeamsPhoneDIDs.ps1 under Modules/' }

    # Stub every CIPP helper the function calls so Pester's Mock has a command to replace.
    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $type) }
    function New-GraphBulkRequest { param($tenantid, $Requests) }
    function Get-CippTeamsNumberType { param($NumberType) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }

    . $FunctionPath
}

Describe 'Remove-CIPPUserTeamsPhoneDIDs' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-GraphBulkRequest -MockWith { }
        Mock -CommandName New-GraphPOSTRequest -MockWith { }
        Mock -CommandName Get-CippException -MockWith { [pscustomobject]@{ NormalizedError = 'boom' } }
        Mock -CommandName Get-CippTeamsNumberType -MockWith { 'directRouting' }
        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                [pscustomobject]@{ telephoneNumber = '+15551000001'; numberType = 'DirectRouting'; assignmentTargetId = 'user-1'; assignmentStatus = 'userAssigned' }
                [pscustomobject]@{ telephoneNumber = '+15551000002'; numberType = 'DirectRouting'; assignmentTargetId = 'user-1'; assignmentStatus = 'userAssigned' }
                [pscustomobject]@{ telephoneNumber = '+15551000003'; numberType = 'CallingPlan'; assignmentTargetId = 'user-2'; assignmentStatus = 'userAssigned' }
                [pscustomobject]@{ telephoneNumber = '+15551000004'; numberType = 'DirectRouting'; assignmentTargetId = 'user-1'; assignmentStatus = 'unassigned' }
            )
        }
    }

    It 'reads the assignments from v1.0 and unassigns each of the user''s numbers on its own request' {
        $Result = Remove-CIPPUserTeamsPhoneDIDs -UserID 'user-1' -Username 'pat@contoso.com' -TenantFilter 'contoso.com'

        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter {
            $uri -eq 'https://graph.microsoft.com/v1.0/admin/teams/telephoneNumberManagement/numberAssignments'
        }
        Should -Invoke New-GraphPOSTRequest -Times 2 -Exactly -ParameterFilter {
            $uri -eq 'https://graph.microsoft.com/v1.0/admin/teams/telephoneNumberManagement/numberAssignments/unassignNumber'
        }
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $body -match '\+15551000001' }
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $body -match '\+15551000002' }
        # An unassigned number and another user's number are left alone.
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly -ParameterFilter { $body -match '\+15551000003|\+15551000004' }
        @($Result)[-1] | Should -Be "Completed processing 2 DIDs for user 'pat@contoso.com': 2 successful, 0 failed"
    }

    It 'never uses a bulk request' {
        $null = Remove-CIPPUserTeamsPhoneDIDs -UserID 'user-1' -TenantFilter 'contoso.com'

        Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
    }

    It 'normalises the number type for the action' {
        $null = Remove-CIPPUserTeamsPhoneDIDs -UserID 'user-1' -TenantFilter 'contoso.com'

        Should -Invoke Get-CippTeamsNumberType -Times 2 -Exactly -ParameterFilter { $NumberType -eq 'DirectRouting' }
        Should -Invoke New-GraphPOSTRequest -Times 2 -Exactly -ParameterFilter { $body -match 'directRouting' }
    }

    It 'reports a failure per number and keeps going' {
        Mock -CommandName New-GraphPOSTRequest -ParameterFilter { $body -match '\+15551000001' } -MockWith { throw 'Number is locked' }

        $Result = Remove-CIPPUserTeamsPhoneDIDs -UserID 'user-1' -Username 'pat@contoso.com' -TenantFilter 'contoso.com'

        @($Result)[0] | Should -BeLike "Failed to remove Teams Phone DID: '+15551000001'*boom"
        @($Result)[1] | Should -BeLike "Successfully removed Teams Phone DID: '+15551000002'*"
        @($Result)[-1] | Should -Be "Completed processing 2 DIDs for user 'pat@contoso.com': 1 successful, 1 failed"
    }

    It 'returns a message and posts nothing when the user has no assigned numbers' {
        $Result = Remove-CIPPUserTeamsPhoneDIDs -UserID 'user-99' -Username 'sam@contoso.com' -TenantFilter 'contoso.com'

        $Result | Should -Be "No Teams Phone DIDs found assigned to user: 'sam@contoso.com' - 'user-99'"
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'returns a message when the tenant has no numbers at all' {
        Mock -CommandName New-GraphGetRequest -MockWith { }

        $Result = Remove-CIPPUserTeamsPhoneDIDs -UserID 'user-1' -TenantFilter 'contoso.com'

        $Result | Should -Be 'No Teams Phone DIDs found in tenant'
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }
}
