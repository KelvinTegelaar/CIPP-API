# Pester tests for Get-SyncroSubdomain.
# Admins paste whatever their browser shows into the Subdomain box; every shape has to come out as
# the bare subdomain the request builder puts in front of .syncromsp.com.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/Syncro/Get-SyncroSubdomain.ps1')
    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/Syncro/Get-SyncroPriority.ps1')
}

Describe 'Get-SyncroSubdomain' {
    It 'returns <Expected> for <Value>' -ForEach @(
        @{ Value = 'contoso'; Expected = 'contoso' }
        @{ Value = '  Contoso  '; Expected = 'contoso' }
        @{ Value = 'contoso.syncromsp.com'; Expected = 'contoso' }
        @{ Value = 'https://contoso.syncromsp.com'; Expected = 'contoso' }
        @{ Value = 'https://contoso.syncromsp.com/tickets?status=open'; Expected = 'contoso' }
        @{ Value = 'http://contoso.syncromsp.com/api/v1'; Expected = 'contoso' }
        @{ Value = ''; Expected = '' }
        @{ Value = $null; Expected = '' }
    ) {
        Get-SyncroSubdomain -Subdomain $Value | Should -Be $Expected
    }
}

Describe 'Get-SyncroPriority' {
    It 'maps <Value> to <Expected>' -ForEach @(
        @{ Value = '0 Urgent'; Expected = '0 Urgent' }
        @{ Value = '1 High'; Expected = '1 High' }
        @{ Value = '2 Normal'; Expected = '2 Normal' }
        @{ Value = '3 Low'; Expected = '3 Low' }
        @{ Value = 'urgent'; Expected = '0 Urgent' }
        @{ Value = 'Low'; Expected = '3 Low' }
        @{ Value = @{ label = 'High'; value = '1 High' }; Expected = '1 High' }
    ) {
        Get-SyncroPriority -Priority $Value | Should -Be $Expected
    }

    It 'rejects <Value> so the caller falls through to the next source' -ForEach @(
        @{ Value = '2' }
        @{ Value = 2 }
        @{ Value = 'Critical' }
        @{ Value = '' }
        @{ Value = $null }
        @{ Value = @{ label = 'Critical'; value = 5 } }
    ) {
        Get-SyncroPriority -Priority $Value | Should -BeNullOrEmpty
    }
}
