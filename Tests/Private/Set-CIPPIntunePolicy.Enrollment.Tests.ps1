# Pester tests for the Apple enrollment (ADE) token binding in the Catalog branch of
# Set-CIPPIntunePolicy.
#
# ADE enrollment policies are Settings Catalog policies that must POST a creationSource binding them
# to the tenant's ADE token ("DepTokenId_{tokenId}"). The token id is per tenant, so templates carry
# a %ADETokenId% placeholder resolved from the tenant's custom variable at deploy time. Without a
# resolved token the DCV2 create fails with an opaque generic error, so deployment fails early with
# the tenant's real token id(s) instead. Ordinary (non-enrollment) Catalog policies are untouched.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    # Stubs mirror the real signatures so signature drift fails loudly here.
    function New-GraphGETRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp, $ComplexFilter) }
    function New-GraphPOSTRequest { [CmdletBinding()] param($uri, $tenantid, $type, $body, $AddedHeaders) }
    function Write-LogMessage { [CmdletBinding()] param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $Sev2, $LogData) }
    function Get-CippException { [CmdletBinding()] param($Exception) }
    function Get-CIPPTextReplacement { [CmdletBinding()] param([string]$TenantFilter, $Text, [switch]$EscapeForJson) }
    function Get-CIPPIntunePolicyName { [CmdletBinding()] param($TemplateType, $RawJSON, $DisplayName) }
    function Select-CIPPIntuneAvailableSetting { [CmdletBinding()] param($Policy, [string]$TenantFilter, [switch]$ThrowOnMissingRequired) }
    function Find-CIPPFuzzyPolicyMatch { [CmdletBinding()] param($DisplayName, $ExistingPolicies, $MaxDistance, $ODataType, $NameProperty, $TemplateId) }
    function Set-CIPPAssignedPolicy { [CmdletBinding()] param($GroupName, $PolicyId, $PlatformType, $Type, $TenantFilter, $ExcludeGroup, $AssignmentMode, $AssignmentFilterName, $AssignmentFilterType) }
    function Sync-CIPPReusablePolicySettings { [CmdletBinding()] param($TemplateInfo, $Tenant) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPIntunePolicy.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'

    function New-EnrollmentPolicy {
        param($CreationSource)
        $Policy = [ordered]@{
            name              = 'iOS_enroll'
            technologies      = 'enrollment'
            templateReference = [ordered]@{ templateId = '27d20e9c_1'; templateFamily = 'enrollmentConfiguration' }
            settings          = @()
        }
        if ($PSBoundParameters.ContainsKey('CreationSource')) { $Policy.creationSource = $CreationSource }
        return ($Policy | ConvertTo-Json -Depth 10)
    }
}

Describe 'Set-CIPPIntunePolicy -TemplateType Catalog (Apple enrollment token binding)' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        # The replacement pass leaves the text as-is here, so an unset %ADETokenId% survives to the gate.
        Mock -CommandName Get-CIPPTextReplacement -MockWith { $Text }
        Mock -CommandName Get-CIPPIntunePolicyName -MockWith { 'iOS_enroll' }
        Mock -CommandName Select-CIPPIntuneAvailableSetting -MockWith { $Policy }
        Mock -CommandName Find-CIPPFuzzyPolicyMatch -MockWith { $null }
        Mock -CommandName Set-CIPPAssignedPolicy -MockWith { }
        # A plain throw normalises to its own message, which is how the reason reaches the caller.
        Mock -CommandName Get-CippException -MockWith { [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }
        # depOnboardingSettings returns the tenant's ADE token(s); everything else (existing policy
        # list) returns nothing so the add path is taken.
        Mock -CommandName New-GraphGETRequest -MockWith {
            if ($uri -match 'depOnboardingSettings') { @([pscustomobject]@{ id = 'TOKEN-ABC' }) } else { @() }
        }
        Mock -CommandName New-GraphPOSTRequest -MockWith { [PSCustomObject]@{ id = 'new-policy-id' } }
    }

    Context 'an enrollment policy whose token placeholder was not resolved' {
        It 'throws a clear error naming the ADETokenId variable and the tenant token id, without posting' {
            $RawJSON = New-EnrollmentPolicy -CreationSource 'DepTokenId_%ADETokenId%'

            { Set-CIPPIntunePolicy -TemplateType 'Catalog' -DisplayName 'iOS_enroll' `
                    -RawJSON $RawJSON -TenantFilter $script:Tenant } |
                Should -Throw -ExpectedMessage '*ADETokenId*TOKEN-ABC*'

            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }
    }

    Context 'an enrollment policy with no creationSource at all (captured before this change)' {
        It 'throws rather than letting Graph fail generically' {
            $RawJSON = New-EnrollmentPolicy

            { Set-CIPPIntunePolicy -TemplateType 'Catalog' -DisplayName 'iOS_enroll' `
                    -RawJSON $RawJSON -TenantFilter $script:Tenant } |
                Should -Throw -ExpectedMessage '*ADE token binding*'

            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }
    }

    Context 'the tenant has no ADE token at all' {
        It 'says so instead of naming a token id' {
            Mock -CommandName New-GraphGETRequest -MockWith { @() }
            $RawJSON = New-EnrollmentPolicy -CreationSource 'DepTokenId_%ADETokenId%'

            { Set-CIPPIntunePolicy -TemplateType 'Catalog' -DisplayName 'iOS_enroll' `
                    -RawJSON $RawJSON -TenantFilter $script:Tenant } |
                Should -Throw -ExpectedMessage '*no Apple ADE/DEP token*'
        }
    }

    Context 'an enrollment policy whose token was resolved to a real id' {
        It 'posts the policy with creationSource intact' {
            $RawJSON = New-EnrollmentPolicy -CreationSource 'DepTokenId_REAL-TOKEN-ID'

            $Result = Set-CIPPIntunePolicy -TemplateType 'Catalog' -DisplayName 'iOS_enroll' `
                -RawJSON $RawJSON -TenantFilter $script:Tenant

            $Result | Should -BeLike '*Successfully added*'
            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $type -eq 'POST' -and ($body | ConvertFrom-Json).creationSource -eq 'DepTokenId_REAL-TOKEN-ID'
            }
        }
    }

    Context 'an ordinary (non-enrollment) Catalog policy with no creationSource' {
        It 'is never gated and deploys normally' {
            $RawJSON = [ordered]@{
                name              = 'Settings Catalog Policy'
                technologies      = 'mdm'
                templateReference = [ordered]@{ templateId = ''; templateFamily = 'none' }
                settings          = @()
            } | ConvertTo-Json -Depth 10

            $Result = Set-CIPPIntunePolicy -TemplateType 'Catalog' -DisplayName 'Settings Catalog Policy' `
                -RawJSON $RawJSON -TenantFilter $script:Tenant

            $Result | Should -BeLike '*Successfully added*'
            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly
        }
    }
}
