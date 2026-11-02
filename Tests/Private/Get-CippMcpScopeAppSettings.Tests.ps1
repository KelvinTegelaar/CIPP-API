# Pester tests for Get-CippMcpScopeAppSettings
# The single source of truth for the MCP OAuth scope app settings written by both
# Invoke-ExecApiClient (Save to Azure) and the Initialize-CIPPAuth warmup reconcile. The whole
# point of the helper is that both callers emit identical values, so these tests pin the exact
# shape: offline_access + the resource scope must appear in every advertised scope set, and the
# CRAFT_PRM / CRAFT_PRM_AS discovery docs appear only on CIPPNG.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/MCP/Get-CippMcpScopeAppSettings.ps1')

    $script:Hostname = 'cipp-backend.azurewebsites.net'
    $script:McpScope = "https://$script:Hostname/user_impersonation"
}

Describe 'Get-CippMcpScopeAppSettings' {
    It 'puts offline_access and the resource scope in the challenge-header scope string' {
        $Settings = Get-CippMcpScopeAppSettings -Hostname $script:Hostname -TenantId 'tenant-guid'
        $Tokens = $Settings['WEBSITE_AUTH_PRM_DEFAULT_WITH_SCOPES'] -split ' '
        $Tokens | Should -Contain 'openid'
        $Tokens | Should -Contain 'profile'
        $Tokens | Should -Contain 'offline_access'
        $Tokens | Should -Contain $script:McpScope
    }

    It 'omits the CRAFT discovery docs when not CIPPNG' {
        $Settings = Get-CippMcpScopeAppSettings -Hostname $script:Hostname -TenantId 'tenant-guid'
        $Settings.ContainsKey('CRAFT_PRM') | Should -BeFalse
        $Settings.ContainsKey('CRAFT_PRM_AS') | Should -BeFalse
    }

    It 'emits CRAFT_PRM and CRAFT_PRM_AS with offline_access in scopes_supported on CIPPNG' {
        $Settings = Get-CippMcpScopeAppSettings -Hostname $script:Hostname -TenantId 'tenant-guid' -IsCippNg

        $Prm = $Settings['CRAFT_PRM'] | ConvertFrom-Json
        $Prm.scopes_supported | Should -Contain 'offline_access'
        $Prm.scopes_supported | Should -Contain $script:McpScope
        $Prm.resource | Should -Be '{origin}/api/ExecMcp'

        $As = $Settings['CRAFT_PRM_AS'] | ConvertFrom-Json
        $As.scopes_supported | Should -Contain 'offline_access'
        $As.grant_types_supported | Should -Contain 'refresh_token'
        $As.token_endpoint | Should -Be 'https://login.microsoftonline.com/tenant-guid/oauth2/v2.0/token'
    }

    It 'is deterministic — repeated calls produce byte-identical values (no restart loop)' {
        $A = Get-CippMcpScopeAppSettings -Hostname $script:Hostname -TenantId 'tenant-guid' -IsCippNg
        $B = Get-CippMcpScopeAppSettings -Hostname $script:Hostname -TenantId 'tenant-guid' -IsCippNg
        $A['WEBSITE_AUTH_PRM_DEFAULT_WITH_SCOPES'] | Should -BeExactly $B['WEBSITE_AUTH_PRM_DEFAULT_WITH_SCOPES']
        $A['CRAFT_PRM'] | Should -BeExactly $B['CRAFT_PRM']
        $A['CRAFT_PRM_AS'] | Should -BeExactly $B['CRAFT_PRM_AS']
    }
}
