# Pester tests for Set-CIPPMCPClientApp
# Focused on the offline_access change: the MCP client app registration must declare
# offline_access (Microsoft Graph, delegated) additively - preserving existing permissions - and
# admin-consent it via Grant-CippAppGraphConsent, so Entra issues a refresh token and clients stop
# re-authenticating every hour.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Set-CIPPMCPClientApp.ps1'

    function New-GraphGetRequest { param($uri, $NoAuthCheck, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $body, $type, $NoAuthCheck, $AsApp) }
    function Get-CippMcpKnownClients { }
    function Grant-CippAppGraphConsent { param($AppId, $Scopes) }
    function Write-LogMessage { param($headers, $API, $message, $Sev) }

    . $FunctionPath

    $script:GraphResourceId = '00000003-0000-0000-c000-000000000000'
    $script:UserRead = 'e1fe6dd8-ba31-4d61-89e7-88639da4683d'
    $script:OfflineAccess = '7427e0e9-2fba-42fe-b0c0-848c9e6a8182'
}

Describe 'Set-CIPPMCPClientApp offline_access' {
    BeforeEach {
        $script:AppId = '55555555-5555-5555-5555-555555555555'
        $script:AppObjectId = 'mcp-app-object-id'

        $script:OriginalHostname = $env:WEBSITE_HOSTNAME
        $env:WEBSITE_HOSTNAME = 'cipp-backend.azurewebsites.net'

        # App starts with only the Graph User.Read delegated permission (what New-CIPPAPIConfig creates).
        $script:AppRequiredResourceAccess = @(
            [PSCustomObject]@{
                resourceAppId  = $script:GraphResourceId
                resourceAccess = @([PSCustomObject]@{ id = $script:UserRead; type = 'Scope' })
            }
        )

        Mock -CommandName Get-CippMcpKnownClients -MockWith {
            [PSCustomObject]@{
                PublicClientRedirectUris = @('https://claude.ai/api/mcp/auth_callback')
                ConfidentialRedirectUris = @('https://global.consent.azure-apim.net/redirect')
                PreAuthorizedClientIds   = @('aebc6443-996d-45c2-90f0-388ff96faa56')
            }
        }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Grant-CippAppGraphConsent -MockWith { [PSCustomObject]@{ AppId = $AppId; Action = 'created'; Scopes = $Scopes } }
        Mock -CommandName New-GraphPOSTRequest -MockWith { }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [PSCustomObject]@{
                id                     = $script:AppObjectId
                appId                  = $script:AppId
                identifierUris         = @("api://$script:AppId")
                api                    = [PSCustomObject]@{ oauth2PermissionScopes = @(); preAuthorizedApplications = @() }
                web                    = [PSCustomObject]@{ redirectUris = @("https://$($env:WEBSITE_HOSTNAME)/.auth/login/aad/callback") }
                spa                    = [PSCustomObject]@{ redirectUris = @() }
                publicClient           = [PSCustomObject]@{ redirectUris = @() }
                requiredResourceAccess = $script:AppRequiredResourceAccess
            }
        }
    }

    AfterEach {
        $env:WEBSITE_HOSTNAME = $script:OriginalHostname
    }

    It 'adds offline_access to the Graph requiredResourceAccess entry, preserving existing scopes' {
        Set-CIPPMCPClientApp -AppId $script:AppId -Headers @{}

        Should -Invoke -CommandName New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $type -eq 'PATCH' -and
            $uri -eq "https://graph.microsoft.com/v1.0/applications/$script:AppObjectId" -and
            $(
                $GraphAccess = (($body | ConvertFrom-Json).requiredResourceAccess | Where-Object { $_.resourceAppId -eq $script:GraphResourceId }).resourceAccess.id
                ($GraphAccess -contains $script:OfflineAccess) -and ($GraphAccess -contains $script:UserRead)
            )
        }
    }

    It 'admin-consents offline_access for the app' {
        Set-CIPPMCPClientApp -AppId $script:AppId -Headers @{}

        Should -Invoke -CommandName Grant-CippAppGraphConsent -Times 1 -Exactly -ParameterFilter {
            $AppId -eq $script:AppId -and ($Scopes -contains 'offline_access')
        }
    }

    It 'does not fail the configuration when the consent grant throws' {
        Mock -CommandName Grant-CippAppGraphConsent -MockWith { throw 'Insufficient privileges' }

        $Result = Set-CIPPMCPClientApp -AppId $script:AppId -Headers @{}

        $Result.Success | Should -BeTrue
    }
}
