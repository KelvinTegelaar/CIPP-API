# Pester tests for how Set-CIPPIntunePolicy forwards group targets to Set-CIPPAssignedPolicy.
#
# The Deploy Policy drawer sends AssignTo/ExcludeGroup as display names. When a single tenant is
# selected it picks groups by id instead and sends GroupIds/ExcludeGroupIds alongside the names;
# those ids must reach Set-CIPPAssignedPolicy, which prefers them over name resolution. Callers
# that send names only (multi-tenant deploys, the IntuneTemplate standard, baselines, clone,
# restore) must see no new parameters at all, so their name-based resolution is untouched.

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
    function Set-CIPPAssignedPolicy { [CmdletBinding()] param($GroupName, $ExcludeGroup, $ExcludeGroupIds, $ExcludeGroupNames, $PolicyId, $Type, $TenantFilter, $PlatformType, $APIName, $Headers, $AssignmentFilterName, $AssignmentFilterType, $GroupIds, $GroupNames, $AssignmentMode, $AssignmentDirection) }
    function Sync-CIPPReusablePolicySettings { [CmdletBinding()] param($TemplateInfo, $Tenant) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPIntunePolicy.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:RawJSON = [ordered]@{
        name              = 'Settings Catalog Policy'
        technologies      = 'mdm'
        templateReference = [ordered]@{ templateId = ''; templateFamily = 'none' }
        settings          = @()
    } | ConvertTo-Json -Depth 10
}

Describe 'Set-CIPPIntunePolicy group id forwarding' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CIPPTextReplacement -MockWith { $Text }
        Mock -CommandName Get-CIPPIntunePolicyName -MockWith { 'Settings Catalog Policy' }
        Mock -CommandName Select-CIPPIntuneAvailableSetting -MockWith { $Policy }
        # No existing policy, so the add path is taken and a fresh id comes back.
        Mock -CommandName Find-CIPPFuzzyPolicyMatch -MockWith { $null }
        Mock -CommandName New-GraphGETRequest -MockWith { @() }
        Mock -CommandName New-GraphPOSTRequest -MockWith { [PSCustomObject]@{ id = 'policy-0001' } }
        Mock -CommandName Set-CIPPAssignedPolicy -MockWith { }
        Mock -CommandName Get-CippException -MockWith { [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }
    }

    Context 'a deploy from the single-tenant picker (ids next to the names)' {
        It 'passes GroupIds and ExcludeGroupIds through, keeping the names as GroupName/ExcludeGroup' {
            $Result = Set-CIPPIntunePolicy -TemplateType 'Catalog' -DisplayName 'Settings Catalog Policy' `
                -RawJSON $script:RawJSON -TenantFilter $script:Tenant `
                -AssignTo 'Sales, Marketing' -ExcludeGroup 'Interns' `
                -GroupIds @('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222') `
                -ExcludeGroupIds @('33333333-3333-3333-3333-333333333333')

            $Result | Should -BeLike '*Successfully added*'
            Should -Invoke Set-CIPPAssignedPolicy -Times 1 -Exactly -ParameterFilter {
                $PolicyId -eq 'policy-0001' -and
                $GroupName -eq 'Sales, Marketing' -and
                $ExcludeGroup -eq 'Interns' -and
                @($GroupIds).Count -eq 2 -and
                $GroupIds[1] -eq '22222222-2222-2222-2222-222222222222' -and
                @($ExcludeGroupIds).Count -eq 1 -and
                $ExcludeGroupIds[0] -eq '33333333-3333-3333-3333-333333333333'
            }
        }
    }

    Context 'a deploy with names only (several tenants, standards, baselines)' {
        It 'does not bind GroupIds or ExcludeGroupIds at all, so name resolution is untouched' {
            $null = Set-CIPPIntunePolicy -TemplateType 'Catalog' -DisplayName 'Settings Catalog Policy' `
                -RawJSON $script:RawJSON -TenantFilter $script:Tenant `
                -AssignTo 'Sales, Marketing' -ExcludeGroup 'Interns'

            Should -Invoke Set-CIPPAssignedPolicy -Times 1 -Exactly -ParameterFilter {
                $GroupName -eq 'Sales, Marketing' -and
                $ExcludeGroup -eq 'Interns' -and
                $null -eq $GroupIds -and
                $null -eq $ExcludeGroupIds
            }
        }
    }

    Context 'a broad target with picked exclusions only' {
        It 'forwards ExcludeGroupIds without inventing GroupIds' {
            $null = Set-CIPPIntunePolicy -TemplateType 'Catalog' -DisplayName 'Settings Catalog Policy' `
                -RawJSON $script:RawJSON -TenantFilter $script:Tenant `
                -AssignTo 'AllDevices' -ExcludeGroup 'Interns' -GroupIds @() `
                -ExcludeGroupIds @('33333333-3333-3333-3333-333333333333')

            Should -Invoke Set-CIPPAssignedPolicy -Times 1 -Exactly -ParameterFilter {
                $GroupName -eq 'AllDevices' -and
                $null -eq $GroupIds -and
                @($ExcludeGroupIds).Count -eq 1
            }
        }
    }
}
