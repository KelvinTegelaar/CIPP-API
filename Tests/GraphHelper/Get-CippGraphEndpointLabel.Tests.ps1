# Pester tests for Get-CippGraphEndpointLabel
# Egress is accounted per Graph resource, so ids, versions and query strings must collapse.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CippGraphEndpointLabel.ps1')
}

Describe 'Get-CippGraphEndpointLabel' {
    It 'normalises <Endpoint> to <Expected>' -TestCases @(
        @{ Endpoint = 'users'; Expected = 'users' }
        @{ Endpoint = '/beta/users?$top=5'; Expected = 'users' }
        @{ Endpoint = 'users/2c1a3b4d-1111-2222-3333-444455556666/memberOf'; Expected = 'users/{id}/memberOf' }
        @{ Endpoint = 'users/jane@contoso.com/mailFolders/inbox'; Expected = 'users/{id}/mailFolders/inbox' }
        @{ Endpoint = "deviceManagement/managedDevices('abc')"; Expected = 'deviceManagement/managedDevices({id})' }
        @{ Endpoint = 'reports/getMailboxUsageDetail(period=''D7'')'; Expected = 'reports/getMailboxUsageDetail({id})' }
    ) {
        Get-CippGraphEndpointLabel -Endpoint $Endpoint | Should -Be $Expected
    }

    It 'returns nothing for an empty endpoint' {
        Get-CippGraphEndpointLabel -Endpoint '' | Should -BeNullOrEmpty
    }
}
