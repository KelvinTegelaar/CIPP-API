# Pester tests for the UpdateAssignments action on Invoke-ExecApplication.

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
    function New-GraphGetRequest { param($Uri, $tenantid, $AsApp) }
    function New-GraphPOSTRequest { param($Uri, $Type, $Body, $tenantid, $AsApp, $AddedHeaders) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $AsApp) }
    function Get-CippProtectedAppId { }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-IsGuid.ps1')

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')
    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Administration/Application Approval/Invoke-ExecApplication.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    $script:SpId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    $script:UserA = '11111111-1111-1111-1111-111111111111'
    $script:GroupA = '22222222-2222-2222-2222-222222222222'
    $script:RoleUser = '33333333-3333-3333-3333-333333333333'
    $script:RoleApp = '44444444-4444-4444-4444-444444444444'

    function New-Sp {
        param([object[]]$AppRoles = @(), [bool]$Required = $false)
        [pscustomobject]@{ id = $script:SpId; displayName = 'My App'; appRoles = $AppRoles; appRoleAssignmentRequired = $Required }
    }
    $script:UserRole = [pscustomobject]@{ id = $script:RoleUser; displayName = 'Reader'; value = 'Reader'; isEnabled = $true; allowedMemberTypes = @('User') }
    $script:AppOnlyRole = [pscustomobject]@{ id = $script:RoleApp; displayName = 'Daemon'; value = 'Daemon'; isEnabled = $true; allowedMemberTypes = @('Application') }

    function New-Request {
        param([hashtable]$Body)
        $Merged = @{ Id = $script:SpId; Type = 'servicePrincipals'; tenantFilter = 'contoso.onmicrosoft.com'; Action = 'UpdateAssignments' }
        foreach ($Key in $Body.Keys) { $Merged[$Key] = $Body[$Key] }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecApplication' }
            Headers = @{}
            Query   = [pscustomobject]@{}
            Body    = [pscustomobject]$Merged
        }
    }
}

Describe 'UpdateAssignments' {
    BeforeEach {
        Mock New-GraphPOSTRequest -MockWith { }
        Mock New-GraphBulkRequest -MockWith {
            foreach ($Request in $Requests) { [pscustomobject]@{ id = $Request.id; status = if ($Request.method -eq 'POST') { 201 } else { 204 } } }
        }
    }

    It 'assigns users and groups with Default Access when the app declares no user roles, and removes assignments' {
        Mock New-GraphGetRequest -MockWith { New-Sp -AppRoles @($script:AppOnlyRole) }

        $Body = @{
            AddUserIds          = @([pscustomobject]@{ label = 'Alice'; value = $script:UserA })
            AddGroupIds         = @([pscustomobject]@{ label = 'Sales'; value = $script:GroupA })
            RemoveAssignmentIds = @([pscustomobject]@{ label = 'Bob (User, Default Access)'; value = 'abc_DEF-123' })
        }
        $Response = Invoke-ExecApplication -Request (New-Request $Body)

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results.resultText | Should -Contain "Assigned Alice to 'My App' as Default Access"
        $Response.Body.Results.resultText | Should -Contain "Removed assignment Bob (User, Default Access) from 'My App'"
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter {
            $Requests.Count -eq 3 -and
            $Requests[0].url -eq "servicePrincipals/$($script:SpId)/appRoleAssignedTo" -and
            $Requests[0].body.principalId -eq $script:UserA -and
            $Requests[0].body.resourceId -eq $script:SpId -and
            $Requests[0].body.appRoleId -eq '00000000-0000-0000-0000-000000000000' -and
            $Requests[1].body.principalId -eq $script:GroupA -and
            $Requests[2].method -eq 'DELETE' -and
            $Requests[2].url -eq "servicePrincipals/$($script:SpId)/appRoleAssignedTo/abc_DEF-123"
        }
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'requires one of the app roles when the app declares user roles' {
        Mock New-GraphGetRequest -MockWith { New-Sp -AppRoles @($script:UserRole) }

        $Missing = Invoke-ExecApplication -Request (New-Request @{ AddUserIds = @($script:UserA) })
        $Missing.StatusCode | Should -Be 400
        $Missing.Body.Results[0].resultText | Should -BeLike '*Reader*'

        $WrongRole = Invoke-ExecApplication -Request (New-Request @{ AddUserIds = @($script:UserA); AppRoleId = $script:RoleApp })
        $WrongRole.StatusCode | Should -Be 400

        $Response = Invoke-ExecApplication -Request (New-Request @{ AddUserIds = @($script:UserA); AppRoleId = [pscustomobject]@{ label = 'Reader'; value = $script:RoleUser } })
        $Response.StatusCode | Should -Be 200
        $Response.Body.Results[0].resultText | Should -BeLike '*as Reader'
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter { $Requests[0].body.appRoleId -eq $script:RoleUser }
    }

    It 'patches assignment required only when it changes' {
        Mock New-GraphGetRequest -MockWith { New-Sp -Required $false }

        $Response = Invoke-ExecApplication -Request (New-Request @{ AppRoleAssignmentRequired = $true })

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results[0].resultText | Should -Be "Turned 'Assignment required' on for 'My App'"
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { $Type -eq 'PATCH' -and $Body -eq '{"appRoleAssignmentRequired":true}' }
        Should -Invoke New-GraphBulkRequest -Times 0

        $Unchanged = Invoke-ExecApplication -Request (New-Request @{ AppRoleAssignmentRequired = $false })
        $Unchanged.StatusCode | Should -Be 400
        $Unchanged.Body.Results[0].resultText | Should -BeLike 'No changes selected*'
    }

    It 'returns 207 when some assignments fail' {
        Mock New-GraphGetRequest -MockWith { New-Sp }
        Mock New-GraphBulkRequest -MockWith {
            [pscustomobject]@{ id = "add-$($script:UserA)"; status = 201 }
            [pscustomobject]@{ id = "add-$($script:GroupA)"; status = 400; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Group-based assignment requires a premium license' } } }
        }

        $Response = Invoke-ExecApplication -Request (New-Request @{ AddUserIds = @($script:UserA); AddGroupIds = @($script:GroupA) })

        $Response.StatusCode | Should -Be 207
        ($Response.Body.Results | Where-Object state -EQ 'error').resultText | Should -BeLike '*premium license*'
    }

    It 'rejects invalid input before calling Graph' {
        Mock New-GraphGetRequest -MockWith { throw 'should not be called' }

        (Invoke-ExecApplication -Request (New-Request @{ Type = 'applications'; AddUserIds = @($script:UserA) })).StatusCode | Should -Be 400
        (Invoke-ExecApplication -Request (New-Request @{ AddUserIds = @('not-a-guid') })).StatusCode | Should -Be 400
        (Invoke-ExecApplication -Request (New-Request @{ RemoveAssignmentIds = @('bad id/../x') })).StatusCode | Should -Be 400
        (Invoke-ExecApplication -Request (New-Request @{ AddUserIds = @($script:UserA); AppRoleId = 'nope' })).StatusCode | Should -Be 400
        Should -Invoke New-GraphGetRequest -Times 0
    }
}
