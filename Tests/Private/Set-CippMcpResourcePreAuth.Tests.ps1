# Pester tests for Set-CippMcpResourcePreAuth - pre-authorizes an MCP client on the CIPP-MCP
# resource's user_impersonation scope so the client -> resource token needs no consent.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Set-CippMcpResourcePreAuth.ps1')

    function New-GraphGetRequest { param($uri, $NoAuthCheck, $asapp) }
    function New-GraphPOSTRequest { param($uri, $body, $type, $NoAuthCheck, $asapp) }
}

Describe 'Set-CippMcpResourcePreAuth' {
    BeforeEach {
        $script:ResourceObjectId = 'res-obj'
        $script:ClientAppId = '55555555-5555-5555-5555-555555555555'
        $script:ScopeId = 'uimp-id'
        Mock -CommandName New-GraphPOSTRequest -MockWith { }
    }

    It 'adds a new client to preAuthorizedApplications and returns true' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [PSCustomObject]@{ api = [PSCustomObject]@{ preAuthorizedApplications = @() } }
        }
        $Result = Set-CippMcpResourcePreAuth -ResourceObjectId $script:ResourceObjectId -ClientAppId $script:ClientAppId -ScopeId $script:ScopeId
        $Result | Should -BeTrue
        Should -Invoke -CommandName New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $type -eq 'PATCH' -and $uri -like '*applications/res-obj*' -and
            $(
                $Pre = ($body | ConvertFrom-Json).api.preAuthorizedApplications
                $Match = $Pre | Where-Object { $_.appId -eq $script:ClientAppId }
                ($Match.delegatedPermissionIds -contains $script:ScopeId)
            )
        }
    }

    It 'is a no-op (no PATCH) when the client is already pre-authorized' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [PSCustomObject]@{ api = [PSCustomObject]@{ preAuthorizedApplications = @(
                        [PSCustomObject]@{ appId = $script:ClientAppId; delegatedPermissionIds = @($script:ScopeId) }
                    ) } }
        }
        $Result = Set-CippMcpResourcePreAuth -ResourceObjectId $script:ResourceObjectId -ClientAppId $script:ClientAppId -ScopeId $script:ScopeId
        $Result | Should -BeFalse
        Should -Invoke -CommandName New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'preserves other pre-authorized clients when adding one' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [PSCustomObject]@{ api = [PSCustomObject]@{ preAuthorizedApplications = @(
                        [PSCustomObject]@{ appId = 'other-client'; delegatedPermissionIds = @('other-scope') }
                    ) } }
        }
        Set-CippMcpResourcePreAuth -ResourceObjectId $script:ResourceObjectId -ClientAppId $script:ClientAppId -ScopeId $script:ScopeId
        Should -Invoke -CommandName New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $Pre = ($body | ConvertFrom-Json).api.preAuthorizedApplications
            (@($Pre.appId) -contains 'other-client') -and (@($Pre.appId) -contains $script:ClientAppId)
        }
    }
}
