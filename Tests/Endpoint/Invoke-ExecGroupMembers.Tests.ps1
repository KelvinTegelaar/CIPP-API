# Pester tests for Invoke-ExecGroupMembers.
#
# Thin switch over Add/Remove-CIPPGroupMember/Owner. The helpers own Graph-vs-Exchange
# routing; this endpoint owns action validation, required-body checks, and HTTP status mapping.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Groups/Invoke-ExecGroupMembers.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Invoke-ExecGroupMembers.ps1 at $FunctionPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Add-CIPPGroupMember { param($Headers, $GroupId, $Member, $TenantFilter, $APIName, $GroupType) }
    function Remove-CIPPGroupMember { param($Headers, $GroupId, $Member, $TenantFilter, $APIName, $GroupType) }
    function Add-CIPPGroupOwner { param($Headers, $GroupId, $Owner, $TenantFilter, $APIName) }
    function Remove-CIPPGroupOwner { param($Headers, $GroupId, $Owner, $TenantFilter, $APIName) }

    . $FunctionPath

    function New-MembersRequest {
        param(
            [string]$Action = 'addMember',
            [string]$GroupId = 'group-guid',
            [string]$TenantFilter = 'contoso.com',
            $Users = @('boss@contoso.com')
        )
        $Body = [ordered]@{}
        if ($null -ne $Action) { $Body.action = $Action }
        if ($null -ne $GroupId) { $Body.groupId = $GroupId }
        if ($null -ne $TenantFilter) { $Body.tenantFilter = $TenantFilter }
        if ($null -ne $Users) { $Body.users = $Users }

        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecGroupMembers' }
            Headers = @{}
            Body    = [pscustomobject]$Body
        }
    }
}

Describe 'Invoke-ExecGroupMembers' {
    BeforeEach {
        Mock -CommandName Add-CIPPGroupMember -MockWith { 'Successfully added member' }
        Mock -CommandName Remove-CIPPGroupMember -MockWith { 'Successfully removed member' }
        Mock -CommandName Add-CIPPGroupOwner -MockWith { 'Successfully added owner' }
        Mock -CommandName Remove-CIPPGroupOwner -MockWith { 'Successfully removed owner' }
    }

    Context 'Request validation' {
        It 'returns BadRequest when action is missing' {
            $Response = Invoke-ExecGroupMembers -Request (New-MembersRequest -Action $null)

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results | Should -BeLike '*Required parameters*'
            Should -Invoke Add-CIPPGroupMember -Times 0 -Exactly
        }

        It 'returns BadRequest when groupId is missing' {
            $Response = Invoke-ExecGroupMembers -Request (New-MembersRequest -GroupId $null)

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            Should -Invoke Add-CIPPGroupMember -Times 0 -Exactly
        }

        It 'returns BadRequest when tenantFilter is missing' {
            $Response = Invoke-ExecGroupMembers -Request (New-MembersRequest -TenantFilter $null)

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            Should -Invoke Add-CIPPGroupMember -Times 0 -Exactly
        }

        It 'returns BadRequest when users is empty' {
            $Response = Invoke-ExecGroupMembers -Request (New-MembersRequest -Users @())

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            Should -Invoke Add-CIPPGroupMember -Times 0 -Exactly
        }

        It 'returns BadRequest for an unknown action' {
            $Response = Invoke-ExecGroupMembers -Request (New-MembersRequest -Action 'renameGroup')

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results | Should -BeLike '*Invalid action*'
            Should -Invoke Add-CIPPGroupMember -Times 0 -Exactly
            Should -Invoke Add-CIPPGroupOwner -Times 0 -Exactly
        }
    }

    Context 'Action routing' {
        It 'calls Add-CIPPGroupMember for addMember' {
            $Response = Invoke-ExecGroupMembers -Request (New-MembersRequest -Action 'addMember' -Users @('one@contoso.com', 'two@contoso.com'))

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            $Response.Body.Results | Should -Be 'Successfully added member'
            Should -Invoke Add-CIPPGroupMember -Times 1 -Exactly -ParameterFilter {
                $GroupId -eq 'group-guid' -and
                $TenantFilter -eq 'contoso.com' -and
                $Member.Count -eq 2 -and
                $Member[0] -eq 'one@contoso.com'
            }
            Should -Invoke Add-CIPPGroupOwner -Times 0 -Exactly
        }

        It 'calls Remove-CIPPGroupMember for removeMember' {
            $Response = Invoke-ExecGroupMembers -Request (New-MembersRequest -Action 'removeMember')

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            Should -Invoke Remove-CIPPGroupMember -Times 1 -Exactly -ParameterFilter {
                $GroupId -eq 'group-guid' -and $Member[0] -eq 'boss@contoso.com'
            }
        }

        It 'calls Add-CIPPGroupOwner for addOwner' {
            $Response = Invoke-ExecGroupMembers -Request (New-MembersRequest -Action 'addOwner')

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            Should -Invoke Add-CIPPGroupOwner -Times 1 -Exactly -ParameterFilter {
                $GroupId -eq 'group-guid' -and $Owner[0] -eq 'boss@contoso.com'
            }
            Should -Invoke Add-CIPPGroupMember -Times 0 -Exactly
        }

        It 'calls Remove-CIPPGroupOwner for removeOwner' {
            $Response = Invoke-ExecGroupMembers -Request (New-MembersRequest -Action 'removeOwner')

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            Should -Invoke Remove-CIPPGroupOwner -Times 1 -Exactly -ParameterFilter {
                $GroupId -eq 'group-guid' -and $Owner[0] -eq 'boss@contoso.com'
            }
        }

        It 'accepts a single user string as well as an array' {
            $Response = Invoke-ExecGroupMembers -Request (New-MembersRequest -Action 'addMember' -Users 'solo@contoso.com')

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            Should -Invoke Add-CIPPGroupMember -Times 1 -Exactly -ParameterFilter {
                $Member.Count -eq 1 -and $Member[0] -eq 'solo@contoso.com'
            }
        }
    }

    Context 'Error mapping' {
        It 'returns InternalServerError when the helper throws' {
            Mock -CommandName Add-CIPPGroupOwner -MockWith { throw 'Failed to add owner boss@contoso.com (user not found)' }

            $Response = Invoke-ExecGroupMembers -Request (New-MembersRequest -Action 'addOwner')

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
            $Response.Body.Results | Should -BeLike '*user not found*'
        }
    }
}
