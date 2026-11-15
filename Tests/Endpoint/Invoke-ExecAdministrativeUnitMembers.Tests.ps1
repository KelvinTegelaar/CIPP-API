# Pester tests for Invoke-ExecAdministrativeUnitMembers.
# Members are added through members/$ref and removed through members/{id}/$ref in one Graph batch
# (Set-CIPPAdministrativeUnitMember), with a per-member result; the status follows Get-CippBulkStatusCode.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/AdministrativeUnits/Invoke-ExecAdministrativeUnitMembers.ps1'

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function New-GraphBulkRequest { param($tenantid, $Requests, $Version) }
    function Get-NormalizedError { param($message) $message }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Test-IsGuid { param([Parameter(Mandatory)][string]$String) [guid]::TryParse($String, [ref][guid]::Empty) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CippExoErrorText.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPAdministrativeUnitMember.ps1')

    . $FunctionPath

    $script:UnitId = '11111111-1111-1111-1111-111111111111'
    $script:UserId = '22222222-2222-2222-2222-222222222222'
    $script:DeviceId = '33333333-3333-3333-3333-333333333333'
    function New-MemberRequest {
        param([hashtable]$Body = @{})
        $RequestBody = @{
            tenantFilter = 'contoso.com'
            action       = 'addMember'
            ID           = $script:UnitId
            displayName  = 'Sales'
            members      = @(@{ value = $script:UserId; label = 'Ann' }, @{ value = $script:DeviceId; label = 'LAPTOP-1' })
        }
        foreach ($Key in $Body.Keys) { $RequestBody[$Key] = $Body[$Key] }
        [pscustomobject]@{ Body = [pscustomobject]$RequestBody; Headers = @{}; Params = @{ CIPPEndpoint = 'ExecAdministrativeUnitMembers' } }
    }
}

Describe 'Invoke-ExecAdministrativeUnitMembers' {
    BeforeEach {
        Mock Write-LogMessage { }
        $script:Requests = $null
        $script:Version = $null
        Mock New-GraphBulkRequest {
            $script:Requests = @($Requests)
            $script:Version = $Version
            foreach ($Request in @($Requests)) { [pscustomobject]@{ id = $Request.id; status = 204 } }
        }
    }

    It 'returns 400 for <Case> without calling Graph' -ForEach @(
        @{ Case = 'an unknown action'; Body = @{ action = 'addOwner' } }
        @{ Case = 'a unit id that is not a GUID'; Body = @{ ID = 'Sales' } }
        @{ Case = 'no members'; Body = @{ members = @() } }
        @{ Case = 'a member given by name'; Body = @{ members = @('ann@contoso.com') } }
    ) {
        $Response = Invoke-ExecAdministrativeUnitMembers -Request (New-MemberRequest -Body $Body)
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results[0].state | Should -BeExactly 'error'
        Should -Invoke New-GraphBulkRequest -Times 0
    }

    It 'adds every member by reference in one batch' {
        $Response = Invoke-ExecAdministrativeUnitMembers -Request (New-MemberRequest)

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke New-GraphBulkRequest -Times 1
        $script:Version | Should -BeExactly 'v1.0'
        $script:Requests.Count | Should -Be 2
        $script:Requests[0].method | Should -BeExactly 'POST'
        $script:Requests[0].url | Should -BeExactly "directory/administrativeUnits/$($script:UnitId)/members/`$ref"
        $script:Requests[0].body.'@odata.id' | Should -BeLike "*/directoryObjects/$($script:UserId)"
        $Response.Body.Results.state | Should -Be @('success', 'success')
        $Response.Body.Results[0].resultText | Should -BeExactly "Added Ann to administrative unit 'Sales'"
    }

    It 'removes a member given as a bare id' {
        $Response = Invoke-ExecAdministrativeUnitMembers -Request (New-MemberRequest -Body @{ action = 'removeMember'; members = @($script:UserId) })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $script:Requests[0].method | Should -BeExactly 'DELETE'
        $script:Requests[0].url | Should -BeLike "*/members/$($script:UserId)/`$ref"
    }

    It 'returns 207 with a result per member when some fail' {
        Mock New-GraphBulkRequest {
            [pscustomobject]@{ id = '1'; status = 204 }
            [pscustomobject]@{ id = '2'; status = 400; body = [pscustomobject]@{ error = [pscustomobject]@{ code = 'Request_BadRequest'; message = 'One or more added object references already exist' } } }
        }

        $Response = Invoke-ExecAdministrativeUnitMembers -Request (New-MemberRequest)

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::MultiStatus)
        $Response.Body.Results.state | Should -Be @('success', 'error')
        $Response.Body.Results[1].resultText | Should -BeExactly "Failed to add LAPTOP-1 to administrative unit 'Sales': One or more added object references already exist"
    }

    It 'fails every member with 500 when the batch itself fails' {
        Mock New-GraphBulkRequest { throw 'Graph unavailable' }

        $Response = Invoke-ExecAdministrativeUnitMembers -Request (New-MemberRequest)

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $Response.Body.Results.state | Should -Be @('error', 'error')
    }
}
