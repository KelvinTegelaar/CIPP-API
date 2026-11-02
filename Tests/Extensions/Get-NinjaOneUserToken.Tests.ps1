# Pester tests for Get-NinjaOneUserToken: the refresh grant and persisting a rotated refresh token.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-ExtensionAPIKey { param([string]$Extension, [switch]$Force) }
    function Set-ExtensionAPIKey { param([string]$Extension, [string]$APIKey) }
    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/NinjaOne/Get-NinjaOneUserToken.ps1')
    $script:Config = [pscustomobject]@{ Instance = 'eu.ninjarmm.com'; ClientID = 'client-id' }
}

Describe 'Get-NinjaOneUserToken' {
    BeforeEach {
        Mock -CommandName Get-ExtensionAPIKey -MockWith {
            param([string]$Extension)
            if ($Extension -eq 'NinjaOneRefreshToken') { 'refresh-1' } else { 'client-secret' }
        }
        Mock -CommandName Set-ExtensionAPIKey -MockWith { $true }
        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $Method, $Body, $ContentType)
            $script:Request = [pscustomobject]@{ Uri = $Uri; Method = $Method; Body = $Body; ContentType = $ContentType }
            @{ access_token = 'access'; refresh_token = $script:NextRefresh; expires_in = 3600 }
        }
        $script:NextRefresh = 'refresh-1'
    }

    It 'posts the refresh grant with the client credentials to the instance token endpoint' {
        $Token = Get-NinjaOneUserToken -Configuration $script:Config
        $Token.access_token | Should -Be 'access'
        $script:Request.Uri | Should -Be 'https://eu.ninjarmm.com/ws/oauth/token'
        $script:Request.Method | Should -Be 'POST'
        $script:Request.ContentType | Should -Be 'application/x-www-form-urlencoded'
        $script:Request.Body.grant_type | Should -Be 'refresh_token'
        $script:Request.Body.refresh_token | Should -Be 'refresh-1'
        $script:Request.Body.client_id | Should -Be 'client-id'
        $script:Request.Body.client_secret | Should -Be 'client-secret'
    }

    It 'stores a rotated refresh token and leaves an unchanged one alone' {
        $null = Get-NinjaOneUserToken -Configuration $script:Config
        Should -Invoke -CommandName Set-ExtensionAPIKey -Times 0
        $script:NextRefresh = 'refresh-2'
        $null = Get-NinjaOneUserToken -Configuration $script:Config
        Should -Invoke -CommandName Set-ExtensionAPIKey -Times 1 -ParameterFilter { $Extension -eq 'NinjaOneRefreshToken' -and $APIKey -eq 'refresh-2' }
    }

    It 'returns nothing without a stored refresh token and never calls the token endpoint' {
        Mock -CommandName Get-ExtensionAPIKey -MockWith { param([string]$Extension) if ($Extension -eq 'NinjaOneRefreshToken') { throw 'not found' } else { 'client-secret' } }
        Get-NinjaOneUserToken -Configuration $script:Config | Should -BeNullOrEmpty
        Should -Invoke -CommandName Invoke-RestMethod -Times 0
    }
}
