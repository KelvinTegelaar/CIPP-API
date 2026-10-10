# Pester tests for New-CIPPMcpResourceApp - the dedicated, CIPP-managed CIPP-MCP resource app that is
# the MCP token audience (holds the host identifier URIs + user_impersonation; never an OAuth client).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/New-CIPPMcpResourceApp.ps1')

    function New-GraphGetRequest { param($uri, $NoAuthCheck, $AsApp, [switch]$ComplexFilter) }
    function New-GraphPOSTRequest { param($uri, $body, $type, $NoAuthCheck, $asapp) }
    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Write-LogMessage { param($headers, $API, $message, $Sev) }
}

Describe 'New-CIPPMcpResourceApp' {
    BeforeEach {
        $script:OriginalHostname = $env:WEBSITE_HOSTNAME
        $env:WEBSITE_HOSTNAME = 'cipp-backend.azurewebsites.net'

        Mock -CommandName Get-CippTable -MockWith { @{} }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }

        # Discovery (by the instance-unique host identifier URI) finds nothing; SP exists; default null.
        Mock -CommandName New-GraphGetRequest -MockWith { $null }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*identifierUris/any*' } -MockWith { @() }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*servicePrincipals*' } -MockWith { [PSCustomObject]@{ id = 'sp-id' } }

        # Create returns the new app already carrying the user_impersonation scope + v2.
        Mock -CommandName New-GraphPOSTRequest -MockWith { }
        Mock -CommandName New-GraphPOSTRequest -ParameterFilter { $uri -eq 'https://graph.microsoft.com/v1.0/applications' -and $type -eq 'POST' } -MockWith {
            [PSCustomObject]@{
                id             = 'res-obj'
                appId          = 'res-app'
                identifierUris = @()
                api            = [PSCustomObject]@{ requestedAccessTokenVersion = 2; oauth2PermissionScopes = @([PSCustomObject]@{ value = 'user_impersonation'; id = 'uimp-id' }) }
            }
        }
    }

    AfterEach {
        $env:WEBSITE_HOSTNAME = $script:OriginalHostname
    }

    It 'creates the resource app, adds host identifier URIs, stores it, and returns the scope id' {
        $Result = New-CIPPMcpResourceApp -Headers @{}

        $Result.AppId | Should -Be 'res-app'
        $Result.ScopeId | Should -Be 'uimp-id'

        Should -Invoke -CommandName New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $uri -eq 'https://graph.microsoft.com/v1.0/applications' -and $type -eq 'POST'
        }
        # A follow-up PATCH adds api://<appId> + the two host identifier URIs.
        Should -Invoke -CommandName New-GraphPOSTRequest -ParameterFilter {
            $type -eq 'PATCH' -and
            (@(($body | ConvertFrom-Json).identifierUris) -contains 'https://cipp-backend.azurewebsites.net/api/ExecMcp')
        }
        Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'throws when WEBSITE_HOSTNAME is not set' {
        $env:WEBSITE_HOSTNAME = ''
        { New-CIPPMcpResourceApp -Headers @{} } | Should -Throw
    }

    It 'warns and throws without creating when a FOREIGN app holds the host URI' {
        # Discovery (name + URI) finds nothing; the conflict check finds a holder that is NOT a
        # CIPP-managed API client (Get-CIPPAzDataTableEntity returns nothing for it). Warn + throw.
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*displayName eq*' } -MockWith { @() }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*identifierUris/any*' -and $uri -notlike '*displayName eq*' } -MockWith {
            @([PSCustomObject]@{ id = 'foreign-obj'; appId = 'foreign-app'; displayName = 'Some Other App' })
        }

        { New-CIPPMcpResourceApp -Headers @{} } | Should -Throw

        Should -Invoke -CommandName New-GraphPOSTRequest -Times 0 -Exactly -ParameterFilter {
            $uri -eq 'https://graph.microsoft.com/v1.0/applications' -and $type -eq 'POST'
        }
        Should -Invoke -CommandName Write-LogMessage -ParameterFilter { $Sev -eq 'Warning' }
    }

    It 'self-heals by freeing the host URI from an OWNED API client, then creates the resource app' {
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*displayName eq*' } -MockWith { @() }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*identifierUris/any*' -and $uri -notlike '*displayName eq*' } -MockWith {
            @([PSCustomObject]@{ id = 'old-obj'; appId = 'old-client'; displayName = 'MCP-NG3.0' })
        }
        # The holder is a CIPP-managed API client.
        Mock -CommandName Get-CIPPAzDataTableEntity -ParameterFilter { $Filter -like "*old-client*" } -MockWith { [PSCustomObject]@{ RowKey = 'old-client' } }
        # The holder app read (for stripping its host URIs).
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like "*appId='old-client'*" } -MockWith {
            [PSCustomObject]@{ id = 'old-obj'; identifierUris = @('api://old-client', 'https://cipp-backend.azurewebsites.net', 'https://cipp-backend.azurewebsites.net/api/ExecMcp') }
        }

        { New-CIPPMcpResourceApp -Headers @{} } | Should -Not -Throw

        # Freed the host URIs from the owned client (PATCH on old-obj that no longer includes them).
        Should -Invoke -CommandName New-GraphPOSTRequest -ParameterFilter {
            $type -eq 'PATCH' -and $uri -like '*applications/old-obj*' -and
            (@(($body | ConvertFrom-Json).identifierUris) -notcontains 'https://cipp-backend.azurewebsites.net/api/ExecMcp')
        }
        # Then created the dedicated resource app.
        Should -Invoke -CommandName New-GraphPOSTRequest -ParameterFilter {
            $uri -eq 'https://graph.microsoft.com/v1.0/applications' -and $type -eq 'POST'
        }
    }
}
