# hasLocalChanges compares this hash against the stamped ContentHash, so it must be stable
# across key order and ignore the fields that change on every save without a real edit
# (tenantFilter, excludedTenants, updatedAt/updatedBy, createdAt).

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPCore/Public/GitHub/Get-CIPPTemplateContentHash.ps1'

    . $FunctionPath
}

Describe 'Get-CIPPTemplateContentHash' {
    It 'hashes equal for the same content with different key order' {
        $A = Get-CIPPTemplateContentHash -JSON '{"a":1,"b":{"y":2,"x":1}}'
        $B = Get-CIPPTemplateContentHash -JSON '{"b":{"x":1,"y":2},"a":1}'
        $A | Should -Be $B
    }

    It 'hashes differ when a value changes' {
        $A = Get-CIPPTemplateContentHash -JSON '{"a":1}'
        $B = Get-CIPPTemplateContentHash -JSON '{"a":2}'
        $A | Should -Not -Be $B
    }

    It 'ignores tenantFilter, excludedTenants and the timestamp/actor fields' {
        $A = Get-CIPPTemplateContentHash -JSON '{"templateName":"Foo","tenantFilter":["t1"],"excludedTenants":["t2"],"updatedAt":"2026-01-01","updatedBy":"a@b.com","createdAt":"2025-01-01"}'
        $B = Get-CIPPTemplateContentHash -JSON '{"templateName":"Foo","tenantFilter":["t9"],"excludedTenants":[],"updatedAt":"2026-09-23","updatedBy":"c@d.com","createdAt":"2020-01-01"}'
        $A | Should -Be $B
    }

    It 'returns a lowercase hex SHA256 string' {
        $Hash = Get-CIPPTemplateContentHash -JSON '{"a":1}'
        $Hash | Should -Match '^[0-9a-f]{64}$'
    }

    It 'returns $null for empty input' {
        Get-CIPPTemplateContentHash -JSON '' | Should -BeNullOrEmpty
    }

    It 'returns $null for unparsable input' {
        Get-CIPPTemplateContentHash -JSON 'not { valid json' | Should -BeNullOrEmpty
    }
}
