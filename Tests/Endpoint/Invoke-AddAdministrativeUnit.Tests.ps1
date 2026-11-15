# Pester tests for Invoke-AddAdministrativeUnit.
# Input is validated before any Graph call; a public unit is sent without visibility (Graph's model of
# public), a dynamic unit with its rule turned on, and restricted management only when asked for. Members
# picked for an assigned unit are added once it exists; a failed member gives 207 but the unit stays.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/AdministrativeUnits/Invoke-AddAdministrativeUnit.ps1'

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body, $asApp) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Get-CippErrorStatusCode { param($ErrorRecord) [System.Net.HttpStatusCode]::InternalServerError }
    function Test-IsGuid { param([Parameter(Mandatory)][string]$String) [guid]::TryParse($String, [ref][guid]::Empty) }
    function Set-CIPPAdministrativeUnitMember { param($TenantFilter, $UnitId, $UnitName, $Action, $Members, $Headers, $APIName) }

    . $FunctionPath

    $script:UserId = '22222222-2222-2222-2222-222222222222'
    function New-AddRequest {
        param([hashtable]$Body = @{})
        $RequestBody = @{ tenantFilter = 'contoso.com'; displayName = 'Sales' }
        foreach ($Key in $Body.Keys) { $RequestBody[$Key] = $Body[$Key] }
        [pscustomobject]@{ Body = [pscustomobject]$RequestBody; Headers = @{}; Params = @{ CIPPEndpoint = 'AddAdministrativeUnit' } }
    }
}

Describe 'Invoke-AddAdministrativeUnit' {
    BeforeEach {
        Mock Write-LogMessage { }
        $script:Posted = $null
        Mock New-GraphPOSTRequest { $script:Posted = $body | ConvertFrom-Json; [pscustomobject]@{ id = 'new-id' } }
        Mock Set-CIPPAdministrativeUnitMember { foreach ($Member in $Members) { @{ resultText = "Added $($Member.label)"; state = 'success' } } }
    }

    It 'returns 400 for <Case> without calling Graph' -ForEach @(
        @{ Case = 'no tenant'; Body = @{ tenantFilter = '' } }
        @{ Case = 'all tenants'; Body = @{ tenantFilter = 'AllTenants' } }
        @{ Case = 'no name'; Body = @{ displayName = '  ' } }
        @{ Case = 'an unknown visibility'; Body = @{ visibility = 'Private' } }
        @{ Case = 'an unknown membership type'; Body = @{ membershipType = 'Mixed' } }
        @{ Case = 'a dynamic unit without a rule'; Body = @{ membershipType = 'Dynamic'; membershipRule = '' } }
        @{ Case = 'members for a dynamic unit'; Body = @{ membershipType = 'Dynamic'; membershipRule = '(user.department -eq "Sales")'; members = @(@{ value = '22222222-2222-2222-2222-222222222222'; label = 'Ann' }) } }
        @{ Case = 'a member given by name'; Body = @{ members = @('ann@contoso.com') } }
    ) {
        $Response = Invoke-AddAdministrativeUnit -Request (New-AddRequest -Body $Body)
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'creates a public assigned unit without a visibility or membership type' {
        $Response = Invoke-AddAdministrativeUnit -Request (New-AddRequest -Body @{ description = ' Sales team ' })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $script:Posted.displayName | Should -BeExactly 'Sales'
        $script:Posted.description | Should -BeExactly 'Sales team'
        $script:Posted.isMemberManagementRestricted | Should -BeFalse
        $script:Posted.PSObject.Properties.Name | Should -Not -Contain 'visibility'
        $script:Posted.PSObject.Properties.Name | Should -Not -Contain 'membershipType'
        @($Response.Body.Results).Count | Should -Be 1
        Should -Invoke Set-CIPPAdministrativeUnitMember -Times 0
    }

    It 'adds the picked members to the new unit' {
        $Response = Invoke-AddAdministrativeUnit -Request (New-AddRequest -Body @{ members = @(@{ value = $script:UserId; label = 'Ann' }) })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results.state | Should -Be @('success', 'success')
        Should -Invoke Set-CIPPAdministrativeUnitMember -Times 1 -ParameterFilter { $UnitId -eq 'new-id' -and $Action -eq 'Add' -and $UnitName -eq 'Sales' }
    }

    It 'returns 207 when the unit is created but a member is not added' {
        Mock Set-CIPPAdministrativeUnitMember { @{ resultText = 'Failed to add Ann'; state = 'error' } }

        $Response = Invoke-AddAdministrativeUnit -Request (New-AddRequest -Body @{ members = @(@{ value = $script:UserId; label = 'Ann' }) })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::MultiStatus)
        $Response.Body.Results[0].resultText | Should -BeExactly "Created administrative unit 'Sales'"
    }

    It 'creates a hidden, restricted, dynamic unit with its rule turned on' {
        $Body = @{ visibility = @{ value = 'HiddenMembership' }; membershipType = 'Dynamic'; membershipRule = '(user.department -eq "Sales")'; isMemberManagementRestricted = $true }
        $null = Invoke-AddAdministrativeUnit -Request (New-AddRequest -Body $Body)

        $script:Posted.visibility | Should -BeExactly 'HiddenMembership'
        $script:Posted.membershipType | Should -BeExactly 'Dynamic'
        $script:Posted.membershipRule | Should -BeExactly '(user.department -eq "Sales")'
        $script:Posted.membershipRuleProcessingState | Should -BeExactly 'On'
        $script:Posted.isMemberManagementRestricted | Should -BeTrue
    }

    It 'returns the upstream status and logs when Graph refuses' {
        Mock New-GraphPOSTRequest { throw 'Request_BadRequest' }

        $Response = Invoke-AddAdministrativeUnit -Request (New-AddRequest -Body @{ members = @(@{ value = $script:UserId; label = 'Ann' }) })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $Response.Body.Results[0].resultText | Should -BeLike "Failed to create administrative unit 'Sales':*"
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $Sev -eq 'Error' }
        Should -Invoke Set-CIPPAdministrativeUnitMember -Times 0
    }
}
