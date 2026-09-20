# Pester tests for Set-CIPPMCPClientApp - configures an MCPAllowed API client as an MCP OAuth client
# against the dedicated CIPP-MCP resource app (split-app model, so refresh is not AADSTS90009).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Set-CIPPMCPClientApp.ps1'

    function New-GraphGetRequest { param($uri, $NoAuthCheck, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $body, $type, $NoAuthCheck, $asapp) }
    function Get-CippMcpKnownClients { }
    function Grant-CippAppGraphConsent { param($AppId, $Scopes, $ResourceAppId) }
    function Write-LogMessage { param($headers, $API, $message, $Sev) }
    function New-CIPPMcpResourceApp { param($Headers) }

    . $FunctionPath

    $script:GraphResourceId = '00000003-0000-0000-c000-000000000000'
    $script:OfflineAccess = '7427e0e9-2fba-42fe-b0c0-848c9e6a8182'
}

Describe 'Set-CIPPMCPClientApp' {
    BeforeEach {
        $script:AppId = '55555555-5555-5555-5555-555555555555'
        $script:AppObjectId = 'client-app-object-id'
        $script:ResourceAppId = 'resource-app'
        $script:ScopeId = 'uimp-id'

        $script:OriginalHostname = $env:WEBSITE_HOSTNAME
        $env:WEBSITE_HOSTNAME = 'cipp-backend.azurewebsites.net'

        Mock -CommandName Get-CippMcpKnownClients -MockWith {
            [PSCustomObject]@{
                PublicClientRedirectUris = @('https://claude.ai/api/mcp/auth_callback')
                ConfidentialRedirectUris = @('https://global.consent.azure-apim.net/redirect')
                PreAuthorizedClientIds   = @('aebc6443-996d-45c2-90f0-388ff96faa56')
            }
        }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Grant-CippAppGraphConsent -MockWith { [PSCustomObject]@{ AppId = $AppId; Action = 'created'; Scopes = $Scopes } }
        Mock -CommandName New-CIPPMcpResourceApp -MockWith { @{ AppId = $script:ResourceAppId; ObjectId = 'res-obj'; ScopeId = $script:ScopeId } }
        Mock -CommandName New-GraphPOSTRequest -MockWith { }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [PSCustomObject]@{
                id                     = $script:AppObjectId
                appId                  = $script:AppId
                identifierUris         = @("api://$script:AppId")
                web                    = [PSCustomObject]@{ redirectUris = @("https://$($env:WEBSITE_HOSTNAME)/.auth/login/aad/callback") }
                spa                    = [PSCustomObject]@{ redirectUris = @() }
                publicClient           = [PSCustomObject]@{ redirectUris = @() }
                requiredResourceAccess = @(
                    [PSCustomObject]@{
                        resourceAppId  = $script:GraphResourceId
                        resourceAccess = @([PSCustomObject]@{ id = 'e1fe6dd8-ba31-4d61-89e7-88639da4683d'; type = 'Scope' })
                    }
                )
            }
        }
    }

    AfterEach {
        $env:WEBSITE_HOSTNAME = $script:OriginalHostname
    }

    It 'ensures the dedicated CIPP-MCP resource app exists' {
        Set-CIPPMCPClientApp -AppId $script:AppId -Headers @{}
        Should -Invoke -CommandName New-CIPPMcpResourceApp -Times 1 -Exactly
    }

    It 'adds the resource user_impersonation permission to the client requiredResourceAccess' {
        Set-CIPPMCPClientApp -AppId $script:AppId -Headers @{}
        Should -Invoke -CommandName New-GraphPOSTRequest -ParameterFilter {
            $type -eq 'PATCH' -and
            $(
                $Rra = ($body | ConvertFrom-Json).requiredResourceAccess
                $ResAccess = ($Rra | Where-Object { $_.resourceAppId -eq $script:ResourceAppId }).resourceAccess.id
                ($ResAccess -contains $script:ScopeId)
            )
        }
    }

    It 'adds the known public callbacks and offline_access to the client' {
        Set-CIPPMCPClientApp -AppId $script:AppId -Headers @{}
        Should -Invoke -CommandName New-GraphPOSTRequest -ParameterFilter {
            $type -eq 'PATCH' -and
            $(
                $Parsed = $body | ConvertFrom-Json
                $GraphAccess = ($Parsed.requiredResourceAccess | Where-Object { $_.resourceAppId -eq $script:GraphResourceId }).resourceAccess.id
                (@($Parsed.publicClient.redirectUris) -contains 'https://claude.ai/api/mcp/auth_callback') -and
                ($GraphAccess -contains $script:OfflineAccess) -and
                ($Parsed.isFallbackPublicClient -eq $true)
            )
        }
    }

    It 'admin-consents the client on the resource user_impersonation scope' {
        Set-CIPPMCPClientApp -AppId $script:AppId -Headers @{}
        Should -Invoke -CommandName Grant-CippAppGraphConsent -ParameterFilter {
            $AppId -eq $script:AppId -and $ResourceAppId -eq $script:ResourceAppId -and ($Scopes -contains 'user_impersonation')
        }
    }

    It 'returns success with the resource app id' {
        $Result = Set-CIPPMCPClientApp -AppId $script:AppId -Headers @{}
        $Result.Success | Should -BeTrue
        $Result.ResourceAppId | Should -Be $script:ResourceAppId
        $Result.ClientAppId | Should -Be $script:AppId
    }

    It 'does not fail the configuration when the consent grant throws' {
        Mock -CommandName Grant-CippAppGraphConsent -MockWith { throw 'Insufficient privileges' }
        $Result = Set-CIPPMCPClientApp -AppId $script:AppId -Headers @{}
        $Result.Success | Should -BeTrue
    }
}
