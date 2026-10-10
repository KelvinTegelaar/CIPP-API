# The Source column carries more than repository names: the baseline migration writes a
# 'StandardsTemplateV2:<guid>' marker and tenant-sourced templates carry a domain. Only
# owner/repo values may read as a GitHub sync.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/GitHub/Test-CIPPRepoSource.ps1')
}

Describe 'Test-CIPPRepoSource' {
    It 'accepts an owner/repo source' {
        Test-CIPPRepoSource -Source 'CyberDrain/CIPP-Templates' | Should -BeTrue
        Test-CIPPRepoSource -Source 'j0eyv/Conditional.Access-Baseline_v2' | Should -BeTrue
    }

    It 'rejects the baseline migration marker' {
        Test-CIPPRepoSource -Source 'StandardsTemplateV2:9c4c44c0-7e0d-4e5d-a018-dd64619c49bc' | Should -BeFalse
    }

    It 'rejects tenant domains, empty and null' {
        Test-CIPPRepoSource -Source 'contoso.onmicrosoft.com' | Should -BeFalse
        Test-CIPPRepoSource -Source '' | Should -BeFalse
        Test-CIPPRepoSource -Source $null | Should -BeFalse
    }
}
