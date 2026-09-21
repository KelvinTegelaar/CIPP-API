# Pester tests for the Admin (administrative template) branch of Set-CIPPIntunePolicy.
#
# Settings from an imported ADMX file bind to definition ids that differ per tenant, so the template's
# binds are resolved to the target tenant's ids before anything is written. When that resolution fails
# the deployment must stop before a policy is created, or an empty policy is left behind.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    # Stubs mirror the real signatures so signature drift fails loudly here.
    function New-GraphGETRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp, $ComplexFilter) }
    function New-GraphPOSTRequest { [CmdletBinding()] param($uri, $tenantid, $type, $body, $AddedHeaders) }
    function Write-LogMessage { [CmdletBinding()] param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $Sev2, $LogData) }
    function Get-CippException { [CmdletBinding()] param($Exception) }
    function Get-CIPPTextReplacement { [CmdletBinding()] param([string]$TenantFilter, $Text, [switch]$EscapeForJson) }
    function Set-CIPPAssignedPolicy { [CmdletBinding()] param($GroupName, $PolicyId, $PlatformType, $Type, $TenantFilter, $ExcludeGroup, $AssignmentMode, $AssignmentFilterName, $AssignmentFilterType) }
    function Resolve-CIPPIntuneAdminTemplateBinding { [CmdletBinding()] param([string]$RawJSON, [string]$TenantFilter, [string]$DisplayName, $Headers, $APIName) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Find-CIPPFuzzyPolicyMatch.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPIntunePolicy.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    # The stored template binds the source tenant's definition id and carries the setting's identity;
    # the resolver's output binds the target tenant's id with the identity removed.
    $script:StoredJSON = [ordered]@{
        added      = @([ordered]@{ 'definition@odata.bind' = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('f65370a6-bc40-40af-b0f3-b6f5481478c0')"; enabled = $true; presentationValues = @(); definition = @{ displayName = 'SPNEGO' } })
        updated    = @()
        deletedIds = @()
    } | ConvertTo-Json -Depth 10 -Compress
    $script:ResolvedJSON = [ordered]@{
        added      = @([ordered]@{ 'definition@odata.bind' = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('11111111-2222-3333-4444-555555555555')"; enabled = $true; presentationValues = @() })
        updated    = @()
        deletedIds = @()
    } | ConvertTo-Json -Depth 10 -Compress
}

Describe 'Set-CIPPIntunePolicy -TemplateType Admin' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CIPPTextReplacement -MockWith { $Text }
        Mock -CommandName Get-CippException -MockWith { [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }
        Mock -CommandName Set-CIPPAssignedPolicy -MockWith { }
        Mock -CommandName Resolve-CIPPIntuneAdminTemplateBinding -MockWith { $script:ResolvedJSON }
        Mock -CommandName New-GraphPOSTRequest -MockWith { [PSCustomObject]@{ id = 'new-policy-id' } }
    }

    Context 'deploying to a tenant that has no policy of that name' {
        BeforeEach {
            Mock -CommandName New-GraphGETRequest -MockWith { @() }
        }

        It 'resolves the binds for the target tenant and writes the resolved payload' {
            $Result = Set-CIPPIntunePolicy -TemplateType 'Admin' -DisplayName 'Firefox' -Description 'desc' -RawJSON $script:StoredJSON -TenantFilter $script:Tenant

            $Result | Should -BeLike '*Successfully added policy*'
            Should -Invoke Resolve-CIPPIntuneAdminTemplateBinding -Times 1 -Exactly -ParameterFilter {
                $RawJSON -eq $script:StoredJSON -and $TenantFilter -eq $script:Tenant -and $DisplayName -eq 'Firefox'
            }
            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $uri -like "*groupPolicyConfigurations('new-policy-id')/updateDefinitionValues" -and $body -eq $script:ResolvedJSON
            }
        }
    }

    Context 'overwriting a policy that already exists' {
        BeforeEach {
            Mock -CommandName New-GraphGETRequest -MockWith {
                if ($uri -like '*/definitionValues') { @([PSCustomObject]@{ id = 'old-value-1' }) }
                else { @([PSCustomObject]@{ id = 'existing-id'; displayName = 'Firefox' }) }
            }
        }

        It 'clears the old values and writes the resolved payload' {
            $Result = Set-CIPPIntunePolicy -TemplateType 'Admin' -DisplayName 'Firefox' -Description 'desc' -RawJSON $script:StoredJSON -TenantFilter $script:Tenant

            $Result | Should -BeLike '*Successfully edited policy*'
            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $uri -like "*groupPolicyConfigurations('existing-id')/updateDefinitionValues" -and $body -like '*"deletedIds":*"old-value-1"*'
            }
            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $uri -like "*groupPolicyConfigurations('existing-id')/updateDefinitionValues" -and $body -eq $script:ResolvedJSON
            }
        }
    }

    Context 'the ADMX behind the template is not imported in the target tenant' {
        BeforeEach {
            Mock -CommandName New-GraphGETRequest -MockWith { @() }
            Mock -CommandName Resolve-CIPPIntuneAdminTemplateBinding -MockWith { throw "Administrative template 'Firefox' uses settings that are not available in $TenantFilter : 'SPNEGO'" }
        }

        It 'fails with the resolver''s explanation before creating any policy' {
            { Set-CIPPIntunePolicy -TemplateType 'Admin' -DisplayName 'Firefox' -Description 'desc' -RawJSON $script:StoredJSON -TenantFilter $script:Tenant } |
                Should -Throw -ExpectedMessage "*not available in $($script:Tenant)*'SPNEGO'*"

            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }
    }
}
