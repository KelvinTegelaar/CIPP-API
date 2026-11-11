# Pester tests for the UpdateOwners action on Invoke-ExecApplication.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }

    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$($Exception.Exception.Message)" } }
    function Get-NormalizedError { param($message) $message }
    function New-GraphBulkRequest { param($Requests, $tenantid, $AsApp) }
    function New-GraphGetRequest { param($Uri, $tenantid, $AsApp) }
    function Get-CippProtectedAppId { }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')
    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Administration/Application Approval/Invoke-ExecApplication.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    $script:UserA = '11111111-1111-1111-1111-111111111111'
    $script:UserB = '22222222-2222-2222-2222-222222222222'

    function New-Request {
        param([hashtable]$Body)
        $Merged = @{ Id = '00000000-0000-0000-0000-0000000000a1'; Type = 'applications'; tenantFilter = 'contoso.onmicrosoft.com'; DisplayName = 'My App' }
        foreach ($Key in $Body.Keys) { $Merged[$Key] = $Body[$Key] }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecApplication' }
            Headers = @{}
            Query   = [pscustomobject]@{}
            Body    = [pscustomobject]$Merged
        }
    }
}

Describe 'UpdateOwners' {
    It 'adds and removes owners in one batch' {
        Mock New-GraphBulkRequest -MockWith {
            foreach ($Request in $Requests) { [pscustomobject]@{ id = $Request.id; status = 204 } }
        }

        $Body = @{
            Action         = 'UpdateOwners'
            AddOwnerIds    = @([pscustomobject]@{ label = 'Alice (alice@contoso.com)'; value = $script:UserA })
            RemoveOwnerIds = @([pscustomobject]@{ label = 'Bob (bob@contoso.com)'; value = $script:UserB })
        }
        $Response = Invoke-ExecApplication -Request (New-Request $Body)

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results.resultText | Should -Contain "Added Alice (alice@contoso.com) as owner of 'My App'"
        $Response.Body.Results.resultText | Should -Contain "Removed Bob (bob@contoso.com) as owner of 'My App'"
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter {
            $Requests.Count -eq 2 -and
            $Requests[0].method -eq 'POST' -and
            $Requests[0].url -eq 'applications/00000000-0000-0000-0000-0000000000a1/owners/$ref' -and
            $Requests[0].body.'@odata.id' -eq "https://graph.microsoft.com/v1.0/directoryObjects/$($script:UserA)" -and
            $Requests[1].method -eq 'DELETE' -and
            $Requests[1].url -eq "applications/00000000-0000-0000-0000-0000000000a1/owners/$($script:UserB)/`$ref"
        }
    }

    It 'accepts only removals on a service principal' {
        Mock New-GraphBulkRequest -MockWith {
            foreach ($Request in $Requests) { [pscustomobject]@{ id = $Request.id; status = 204 } }
        }

        $Response = Invoke-ExecApplication -Request (New-Request @{ Action = 'UpdateOwners'; Type = 'servicePrincipals'; Id = '00000000-0000-0000-0000-0000000000b1'; RemoveOwnerIds = @($script:UserA) })

        $Response.StatusCode | Should -Be 200
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter {
            $Requests.Count -eq 1 -and $Requests[0].url -eq "servicePrincipals/00000000-0000-0000-0000-0000000000b1/owners/$($script:UserA)/`$ref"
        }
    }

    It 'returns 207 when some changes fail and 500 when all fail' {
        Mock New-GraphBulkRequest -MockWith {
            [pscustomobject]@{ id = $script:UserA; status = 204 }
            [pscustomobject]@{ id = $script:UserB; status = 400; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'One or more added object references already exist' } } }
        }
        $Partial = Invoke-ExecApplication -Request (New-Request @{ Action = 'UpdateOwners'; AddOwnerIds = @($script:UserA, $script:UserB) })
        $Partial.StatusCode | Should -Be 207
        ($Partial.Body.Results | Where-Object state -EQ 'error').resultText | Should -BeLike '*already exist*'

        Mock New-GraphBulkRequest -MockWith {
            [pscustomobject]@{ id = $script:UserA; status = 404; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Resource not found' } } }
        }
        (Invoke-ExecApplication -Request (New-Request @{ Action = 'UpdateOwners'; RemoveOwnerIds = @($script:UserA) })).StatusCode | Should -Be 500
    }

    It 'rejects empty, invalid or conflicting selections before calling Graph' {
        Mock New-GraphBulkRequest -MockWith { throw 'should not be called' }

        (Invoke-ExecApplication -Request (New-Request @{ Action = 'UpdateOwners' })).StatusCode | Should -Be 400
        (Invoke-ExecApplication -Request (New-Request @{ Action = 'UpdateOwners'; AddOwnerIds = @('not-a-guid') })).StatusCode | Should -Be 400
        (Invoke-ExecApplication -Request (New-Request @{ Action = 'UpdateOwners'; AddOwnerIds = @($script:UserA); RemoveOwnerIds = @($script:UserA) })).StatusCode | Should -Be 400
        Should -Invoke New-GraphBulkRequest -Times 0
    }
}
