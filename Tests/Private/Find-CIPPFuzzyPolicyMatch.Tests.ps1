# Pester tests for Find-CIPPFuzzyPolicyMatch
# Verifies exact matching, fuzzy matching, sub-type filtering, property selection,
# and edge cases.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $LevenshteinPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Get-CIPPLevenshteinDistance.ps1'
    $FuzzyPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Find-CIPPFuzzyPolicyMatch.ps1'

    if (-not (Test-Path -Path $LevenshteinPath)) {
        $LevenshteinPath = Join-Path $RepoRoot 'Modules/CIPPCore/Private/Get-CIPPLevenshteinDistance.ps1'
    }
    if (-not (Test-Path -Path $FuzzyPath)) {
        $FuzzyPath = Join-Path $RepoRoot 'Modules/CIPPCore/Private/Find-CIPPFuzzyPolicyMatch.ps1'
    }

    . $LevenshteinPath
    . $FuzzyPath

    # Helper to build minimal policy objects
    function New-FakePolicy {
        param(
            [string]$DisplayName,
            [string]$ODataType,
            [string]$TemplateId,
            [string]$Id = [System.Guid]::NewGuid().ToString(),
            [datetime]$LastModified = (Get-Date)
        )
        [PSCustomObject]@{
            id                   = $Id
            displayName          = $DisplayName
            '@odata.type'        = $ODataType
            templateReference    = if ($TemplateId) { [PSCustomObject]@{ templateId = $TemplateId } } else { $null }
            lastModifiedDateTime = $LastModified
        }
    }

    function New-FakeCatalogPolicy {
        param(
            [string]$Name,
            [string]$TemplateId,
            [string]$Id = [System.Guid]::NewGuid().ToString(),
            [datetime]$LastModified = (Get-Date)
        )
        [PSCustomObject]@{
            id                   = $Id
            name                 = $Name
            templateReference    = if ($TemplateId) { [PSCustomObject]@{ templateId = $TemplateId } } else { $null }
            lastModifiedDateTime = $LastModified
        }
    }
}

Describe 'Find-CIPPFuzzyPolicyMatch' {

    Context 'Null / empty collection' {
        It 'returns $null for a null collection' {
            $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'My Policy' -ExistingPolicies $null -MaxDistance 5
            $result | Should -BeNullOrEmpty
        }

        It 'returns $null for an empty array' {
            $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'My Policy' -ExistingPolicies @() -MaxDistance 5
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Exact matching (MaxDistance = 0)' {
        It 'returns the matching policy when name is an exact match' {
            $policies = @(
                New-FakePolicy -DisplayName 'My Policy'
                New-FakePolicy -DisplayName 'Other Policy'
            )
            $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'My Policy' -ExistingPolicies $policies -MaxDistance 0
            $result | Should -Not -BeNullOrEmpty
            $result.MatchType | Should -Be 'exact'
            $result.Distance | Should -Be 0
            $result.Policy.displayName | Should -Be 'My Policy'
        }

        It 'returns $null when there is no exact match and MaxDistance is 0' {
            $policies = @(
                New-FakePolicy -DisplayName 'My Policy v2'
            )
            $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'My Policy v1' -ExistingPolicies $policies -MaxDistance 0
            $result | Should -BeNullOrEmpty
        }

        It 'is case-insensitive for exact matching' {
            $policies = @(New-FakePolicy -DisplayName 'My Policy')
            $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'my policy' -ExistingPolicies $policies -MaxDistance 0
            # Exact match check is -eq which is case-insensitive in PowerShell by default
            $result | Should -Not -BeNullOrEmpty
            $result.MatchType | Should -Be 'exact'
        }
    }

    Context 'Fuzzy matching' {
        It 'finds a policy within the allowed distance (distance=3, actual=3)' {
            $policies = @(
                New-FakePolicy -DisplayName 'Win - OIB - SC - Device Security - v3.6'
            )
            # "Win - OIB - SC - Device Security - v4.0" vs "v3.6": change 3 characters -> distance 3
            $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'Win - OIB - SC - Device Security - v4.0' -ExistingPolicies $policies -MaxDistance 3
            $result | Should -Not -BeNullOrEmpty
            $result.MatchType | Should -Be 'fuzzy'
            $result.Distance | Should -BeLessOrEqual 3
        }

        It 'does not find a policy when distance exceeds MaxDistance' {
            $policies = @(
                New-FakePolicy -DisplayName 'Completely Different Name XYZ'
            )
            $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'My Policy' -ExistingPolicies $policies -MaxDistance 2
            $result | Should -BeNullOrEmpty
        }

        It 'prefers exact match over fuzzy match when both could exist' {
            $policies = @(
                New-FakePolicy -DisplayName 'My Policy v1'
                New-FakePolicy -DisplayName 'My Policy'
            )
            $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'My Policy' -ExistingPolicies $policies -MaxDistance 5
            $result.MatchType | Should -Be 'exact'
            $result.Distance | Should -Be 0
        }

        It 'picks the closest match when multiple policies are within threshold' {
            $policies = @(
                New-FakePolicy -DisplayName 'My Policy v3'   # distance from 'My Policy v1' = 1
                New-FakePolicy -DisplayName 'My Policy v22'  # distance from 'My Policy v1' = 2
            )
            $dist1 = Get-CIPPLevenshteinDistance -Source 'my policy v1' -Target 'my policy v3'
            $dist2 = Get-CIPPLevenshteinDistance -Source 'my policy v1' -Target 'my policy v22'
            $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'My Policy v1' -ExistingPolicies $policies -MaxDistance 5
            $result.MatchType | Should -Be 'fuzzy'
            $result.Distance | Should -Be ([Math]::Min($dist1, $dist2))
        }

        It 'uses lastModifiedDateTime as tie-breaker when distances are equal' {
            $older  = New-FakePolicy -DisplayName 'My Policy v3' -Id 'older'  -LastModified (Get-Date).AddDays(-5)
            $newer  = New-FakePolicy -DisplayName 'My Policy v3' -Id 'newer'  -LastModified (Get-Date)
            $policies = @($older, $newer)
            $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'My Policy v1' -ExistingPolicies $policies -MaxDistance 5
            $result.Policy.id | Should -Be 'newer'
        }
    }

    Context '@odata.type sub-type filtering' {
        It 'returns $null when ODataType is set and no candidate matches the type' {
            $policies = @(
                New-FakePolicy -DisplayName 'My Policy v2' -ODataType '#microsoft.graph.iosCompliancePolicy'
            )
            $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'My Policy v1' -ExistingPolicies $policies `
                -MaxDistance 5 -ODataType '#microsoft.graph.windows10CompliancePolicy'
            $result | Should -BeNullOrEmpty
        }

        It 'returns a match when ODataType matches' {
            $policies = @(
                New-FakePolicy -DisplayName 'My Policy v2' -ODataType '#microsoft.graph.windows10CompliancePolicy'
            )
            $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'My Policy v1' -ExistingPolicies $policies `
                -MaxDistance 5 -ODataType '#microsoft.graph.windows10CompliancePolicy'
            $result | Should -Not -BeNullOrEmpty
        }

        It 'ignores ODataType when ODataType parameter is not provided' {
            $policies = @(
                New-FakePolicy -DisplayName 'My Policy v2' -ODataType '#microsoft.graph.iosCompliancePolicy'
            )
            $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'My Policy v1' -ExistingPolicies $policies -MaxDistance 5
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Catalog templateId filtering' {
        It 'returns $null when TemplateId is set and no candidate matches' {
            $policies = @(
                New-FakeCatalogPolicy -Name 'My Policy v2' -TemplateId 'template-b'
            )
            $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'My Policy v1' -ExistingPolicies $policies `
                -MaxDistance 5 -NameProperty 'name' -TemplateId 'template-a'
            $result | Should -BeNullOrEmpty
        }

        It 'returns a match when TemplateId matches' {
            $policies = @(
                New-FakeCatalogPolicy -Name 'My Policy v2' -TemplateId 'template-a'
            )
            $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'My Policy v1' -ExistingPolicies $policies `
                -MaxDistance 5 -NameProperty 'name' -TemplateId 'template-a'
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Catalog name property support' {
        It 'uses the name property when NameProperty is set to name' {
            $policy = New-FakeCatalogPolicy -Name 'Catalog Policy'
            $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'Catalog Policy' -ExistingPolicies @($policy) -NameProperty 'name'
            $result | Should -Not -BeNullOrEmpty
            $result.MatchType | Should -Be 'exact'
            $result.OriginalName | Should -Be 'Catalog Policy'
        }

        It 'does not match when trying displayName on a Catalog policy' {
            $policy = New-FakeCatalogPolicy -Name 'Catalog Policy'
            # The catalog policy has no 'displayName' — so exact match against 'displayName' yields nothing
            $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'Catalog Policy' -ExistingPolicies @($policy) -NameProperty 'displayName'
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Return value structure' {
        It 'returns an object with Policy, MatchType, Distance, and OriginalName properties' {
            $policy = New-FakePolicy -DisplayName 'My Policy'
            $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'My Policy' -ExistingPolicies @($policy)
            $result.PSObject.Properties.Name | Should -Contain 'Policy'
            $result.PSObject.Properties.Name | Should -Contain 'MatchType'
            $result.PSObject.Properties.Name | Should -Contain 'Distance'
            $result.PSObject.Properties.Name | Should -Contain 'OriginalName'
        }

        It 'OriginalName reflects the existing policy name, not the template name' {
            $policy = New-FakePolicy -DisplayName 'My Policy v3'
            $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'My Policy v1' -ExistingPolicies @($policy) -MaxDistance 5
            $result.OriginalName | Should -Be 'My Policy v3'
        }
    }
}
