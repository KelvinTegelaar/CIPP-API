# Pester tests for Invoke-EditAdministrativeUnit.
# Only the fields sent are patched. Public visibility is sent as null (Graph's model of public), switching
# to assigned clears the rule, and a request that changes nothing is refused before any Graph call. Members
# are added and removed after the patch, and only the members are changed when nothing else is.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/AdministrativeUnits/Invoke-EditAdministrativeUnit.ps1'

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
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')

    . $FunctionPath

    $script:UnitId = '11111111-1111-1111-1111-111111111111'
    $script:UserId = '22222222-2222-2222-2222-222222222222'
    function New-EditRequest {
        param([hashtable]$Body = @{})
        $RequestBody = @{ tenantFilter = 'contoso.com'; ID = $script:UnitId; currentDisplayName = 'Sales' }
        foreach ($Key in $Body.Keys) { $RequestBody[$Key] = $Body[$Key] }
        [pscustomobject]@{ Body = [pscustomobject]$RequestBody; Headers = @{}; Params = @{ CIPPEndpoint = 'EditAdministrativeUnit' } }
    }
}

Describe 'Invoke-EditAdministrativeUnit' {
    BeforeEach {
        Mock Write-LogMessage { }
        $script:Patch = $null
        $script:Uri = $null
        Mock New-GraphPOSTRequest { $script:Uri = $uri; $script:Patch = $body | ConvertFrom-Json -AsHashtable }
        Mock Set-CIPPAdministrativeUnitMember { foreach ($Member in $Members) { @{ resultText = "$Action $($Member.label)"; state = 'success' } } }
    }

    It 'returns 400 for <Case> without calling Graph' -ForEach @(
        @{ Case = 'an id that is not a GUID'; Body = @{ ID = 'sales'; displayName = 'Sales' } }
        @{ Case = 'an empty name'; Body = @{ displayName = ' ' } }
        @{ Case = 'an unknown processing state'; Body = @{ membershipRuleProcessingState = 'Off' } }
        @{ Case = 'dynamic without a rule'; Body = @{ membershipType = 'Dynamic' } }
        @{ Case = 'nothing to change'; Body = @{} }
        @{ Case = 'nothing to change but empty member lists'; Body = @{ AddMember = @(); RemoveMember = @() } }
        @{ Case = 'members for a dynamic unit'; Body = @{ membershipType = 'Dynamic'; membershipRule = '(user.department -eq "Sales")'; AddMember = @(@{ value = '22222222-2222-2222-2222-222222222222'; label = 'Ann' }) } }
        @{ Case = 'a member given by name'; Body = @{ RemoveMember = @('ann@contoso.com') } }
    ) {
        $Response = Invoke-EditAdministrativeUnit -Request (New-EditRequest -Body $Body)
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'patches only the fields sent' {
        $Response = Invoke-EditAdministrativeUnit -Request (New-EditRequest -Body @{ description = 'New' })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $script:Uri | Should -BeLike "*/directory/administrativeUnits/$($script:UnitId)"
        @($script:Patch.Keys) | Should -Be @('description')
    }

    It 'sends public visibility as null' {
        $null = Invoke-EditAdministrativeUnit -Request (New-EditRequest -Body @{ visibility = 'Public' })

        $script:Patch.ContainsKey('visibility') | Should -BeTrue
        $script:Patch.visibility | Should -BeNullOrEmpty
    }

    It 'clears the rule when a unit becomes assigned' {
        $null = Invoke-EditAdministrativeUnit -Request (New-EditRequest -Body @{ membershipType = 'Assigned' })

        $script:Patch.membershipType | Should -BeExactly 'Assigned'
        $script:Patch.ContainsKey('membershipRule') | Should -BeTrue
        $script:Patch.membershipRule | Should -BeNullOrEmpty
    }

    It 'pauses a dynamic rule on its own' {
        $null = Invoke-EditAdministrativeUnit -Request (New-EditRequest -Body @{ membershipRuleProcessingState = 'Paused' })

        @($script:Patch.Keys) | Should -Be @('membershipRuleProcessingState')
        $script:Patch.membershipRuleProcessingState | Should -BeExactly 'Paused'
    }

    It 'changes only the members when nothing else is sent' {
        $Body = @{ AddMember = @(@{ value = $script:UserId; label = 'Ann' }); RemoveMember = @(@{ value = '33333333-3333-3333-3333-333333333333'; label = 'Bob' }) }
        $Response = Invoke-EditAdministrativeUnit -Request (New-EditRequest -Body $Body)

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke New-GraphPOSTRequest -Times 0
        Should -Invoke Set-CIPPAdministrativeUnitMember -Times 1 -ParameterFilter { $Action -eq 'Add' -and $UnitId -eq $script:UnitId -and $UnitName -eq 'Sales' }
        Should -Invoke Set-CIPPAdministrativeUnitMember -Times 1 -ParameterFilter { $Action -eq 'Remove' }
        $Response.Body.Results.resultText | Should -Be @('Add Ann', 'Remove Bob')
    }

    It 'still changes the members and returns 207 when the unit update fails' {
        Mock New-GraphPOSTRequest { throw 'Request_BadRequest' }

        $Response = Invoke-EditAdministrativeUnit -Request (New-EditRequest -Body @{ description = 'New'; AddMember = @(@{ value = $script:UserId; label = 'Ann' }) })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::MultiStatus)
        $Response.Body.Results.state | Should -Be @('error', 'success')
    }

    It 'returns the upstream status when only the unit update was asked for and fails' {
        Mock New-GraphPOSTRequest { throw 'Request_BadRequest' }

        $Response = Invoke-EditAdministrativeUnit -Request (New-EditRequest -Body @{ description = 'New' })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $Response.Body.Results[0].resultText | Should -BeLike "Failed to update administrative unit 'Sales':*"
    }
}
