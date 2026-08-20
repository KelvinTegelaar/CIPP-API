# Pester tests for Resolve-CIPPDirectoryId.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Resolve-CIPPDirectoryId.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Resolve-CIPPDirectoryId.ps1 under Modules/' }

    function New-GraphPOSTRequest { param($uri, $tenantid, $body) }
    function New-GraphBulkRequest { param($Requests, $tenantid) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function Write-Information { param($MessageData) }

    . $FunctionPath
}

Describe 'Resolve-CIPPDirectoryId' {
    It 'returns an empty array for empty input' {
        $Result = Resolve-CIPPDirectoryId -Identity @() -TenantFilter 'contoso.com'
        @($Result).Count | Should -Be 0
    }

    It 'resolves GUID identities via getByIds' {
        Mock -CommandName New-GraphPOSTRequest -MockWith {
            [pscustomobject]@{
                value = @(
                    [pscustomobject]@{ id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; userPrincipalName = 'a@contoso.com'; displayName = 'Alice' }
                )
            }
        }

        $Result = Resolve-CIPPDirectoryId -Identity @('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee') -TenantFilter 'contoso.com'

        $Result.Count | Should -Be 1
        $Result[0].Resolved | Should -BeTrue
        $Result[0].Id | Should -Be 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $Result[0].UserPrincipalName | Should -Be 'a@contoso.com'
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly
    }

    It 'resolves a GUID group via getByIds with @odata.type group' {
        $GroupGuid = 'bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee'
        Mock -CommandName New-GraphBulkRequest -MockWith { @() }
        Mock -CommandName New-GraphPOSTRequest -MockWith {
            [pscustomobject]@{
                value = @(
                    [pscustomobject]@{
                        id            = $GroupGuid
                        displayName   = 'Nested SG'
                        mail          = 'nested@contoso.com'
                        mailNickname  = 'nested'
                        mailEnabled   = $false
                        groupTypes    = @()
                        '@odata.type' = '#microsoft.graph.group'
                    }
                )
            }
        }

        $Result = Resolve-CIPPDirectoryId -Identity @($GroupGuid) -TenantFilter 'contoso.com'

        $Result[0].Resolved | Should -BeTrue
        $Result[0].Id | Should -Be $GroupGuid
        $Result[0].Type | Should -Be 'Group'
        $Result[0].ODataType | Should -Be '#microsoft.graph.group'
        $Result[0].Label | Should -Be 'Nested SG'
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly
        Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
    }

    It 'resolves UPNs via users/{identity}' {
        Mock -CommandName New-GraphBulkRequest -MockWith {
            @(
                [pscustomobject]@{
                    id     = 'user-bob@contoso.com'
                    status = 200
                    body   = [pscustomobject]@{ id = 'bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee'; userPrincipalName = 'bob@contoso.com'; displayName = 'Bob' }
                }
            )
        }

        $Result = Resolve-CIPPDirectoryId -Identity @('bob@contoso.com') -TenantFilter 'contoso.com'

        $Result[0].Resolved | Should -BeTrue
        $Result[0].Id | Should -Be 'bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee'
        $Result[0].Input | Should -Be 'bob@contoso.com'
    }

    It 'falls through users 404 then resolves non-GUID mail via group filter' {
        Mock -CommandName New-GraphBulkRequest -MockWith {
            @([pscustomobject]@{ id = 'user-nested@contoso.com'; status = 404; body = $null })
        }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{
                id           = 'cccccccc-bbbb-cccc-dddd-eeeeeeeeeeee'
                displayName  = 'Nested by mail'
                mail         = 'nested@contoso.com'
                mailNickname = 'nested'
                mailEnabled  = $true
                groupTypes   = @()
            }
        }

        $Result = Resolve-CIPPDirectoryId -Identity @('nested@contoso.com') -TenantFilter 'contoso.com'

        $Result[0].Resolved | Should -BeTrue
        $Result[0].Id | Should -Be 'cccccccc-bbbb-cccc-dddd-eeeeeeeeeeee'
        $Result[0].Type | Should -Be 'Group'
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter {
            $uri -like '*groups?*filter=*' -and ($uri -like '*nested@contoso.com*' -or $uri -like '*nested%40contoso.com*')
        }
    }

    It 'marks unresolved identities without throwing' {
        Mock -CommandName New-GraphBulkRequest -MockWith {
            @([pscustomobject]@{ id = 'user-missing@contoso.com'; status = 404; body = $null })
        }
        Mock -CommandName New-GraphGetRequest -MockWith { @() }

        $Result = Resolve-CIPPDirectoryId -Identity @('missing@contoso.com') -TenantFilter 'contoso.com'

        $Result[0].Resolved | Should -BeFalse
        $Result[0].Id | Should -BeNullOrEmpty
    }

    It 'normalizes a UPN and a GUID for the same user to the same id' {
        Mock -CommandName New-GraphPOSTRequest -MockWith {
            [pscustomobject]@{
                value = @([pscustomobject]@{ id = 'cccccccc-bbbb-cccc-dddd-eeeeeeeeeeee'; userPrincipalName = 'c@contoso.com'; displayName = 'C' })
            }
        }
        Mock -CommandName New-GraphBulkRequest -MockWith {
            @([pscustomobject]@{
                    id     = 'user-c@contoso.com'
                    status = 200
                    body   = [pscustomobject]@{ id = 'cccccccc-bbbb-cccc-dddd-eeeeeeeeeeee'; userPrincipalName = 'c@contoso.com'; displayName = 'C' }
                })
        }

        $Result = Resolve-CIPPDirectoryId -Identity @('c@contoso.com', 'cccccccc-bbbb-cccc-dddd-eeeeeeeeeeee') -TenantFilter 'contoso.com'

        ($Result | Where-Object Resolved).Id | Select-Object -Unique | Should -Be 'cccccccc-bbbb-cccc-dddd-eeeeeeeeeeee'
    }
}
