# Pester tests for Invoke-CIPPStandardDisableAgentBlueprintCreation.
#
# The agent identity blueprint switch lives next to allowedToCreateApps on the authorization
# policy but is independent of it: a tenant with app registration disabled still lets every
# user create blueprints. These tests pin that the standard reads and writes ONLY the
# blueprint flag and never touches the sibling app-registration flag.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Join-Path $RepoRoot 'Modules/CIPPStandards/Public/Standards/Invoke-CIPPStandardDisableAgentBlueprintCreation.ps1'

    function New-GraphGetRequest { [CmdletBinding()] param($Uri, $tenantid, $AsApp) }
    function New-GraphPostRequest { [CmdletBinding()] param($tenantid, $Uri, $Type, $Body, $AsApp, $ContentType) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }

    . $StandardPath
    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Invoke-CIPPStandardDisableAgentBlueprintCreation' {
    BeforeEach {
        Mock New-GraphGetRequest {
            [PSCustomObject]@{
                defaultUserRolePermissions = [PSCustomObject]@{
                    allowedToCreateApps                    = $false
                    allowedToCreateAgentIdentityBlueprints = $true
                    allowedToCreateSecurityGroups          = $false
                }
            }
        }
        Mock New-GraphPostRequest { }
        Mock Write-LogMessage { }
        Mock Write-StandardsAlert { }
        Mock Set-CIPPStandardsCompareField { }
    }

    It 'patches only the agent identity blueprint flag when users may still create blueprints' {
        Invoke-CIPPStandardDisableAgentBlueprintCreation -Tenant $script:Tenant -Settings @{ remediate = $true }

        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $Type -eq 'patch' -and
            $Uri -like '*policies/authorizationPolicy/authorizationPolicy' -and
            ($Body | ConvertFrom-Json).defaultUserRolePermissions.allowedToCreateAgentIdentityBlueprints -eq $false -and
            $null -eq ($Body | ConvertFrom-Json).defaultUserRolePermissions.PSObject.Properties['allowedToCreateApps']
        }
    }

    It 'does not write or alert when blueprint creation is already disabled' {
        Mock New-GraphGetRequest {
            [PSCustomObject]@{
                defaultUserRolePermissions = [PSCustomObject]@{
                    allowedToCreateApps                    = $true
                    allowedToCreateAgentIdentityBlueprints = $false
                }
            }
        }

        Invoke-CIPPStandardDisableAgentBlueprintCreation -Tenant $script:Tenant -Settings @{ remediate = $true; alert = $true }

        Should -Invoke New-GraphPostRequest -Times 0 -Exactly
        Should -Invoke Write-StandardsAlert -Times 0 -Exactly
    }

    It 'alerts when users can create blueprints even though app registration is disabled' {
        Invoke-CIPPStandardDisableAgentBlueprintCreation -Tenant $script:Tenant -Settings @{ alert = $true; standardId = 'std-1' }

        Should -Invoke Write-StandardsAlert -Times 1 -Exactly -ParameterFilter {
            $standardName -eq 'DisableAgentBlueprintCreation' -and $standardId -eq 'std-1'
        }
    }

    It 'reports only the blueprint flag as the comparison field' {
        Invoke-CIPPStandardDisableAgentBlueprintCreation -Tenant $script:Tenant -Settings @{ report = $true }

        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
            $FieldName -eq 'standards.DisableAgentBlueprintCreation' -and
            $CurrentValue.allowedToCreateAgentIdentityBlueprints -eq $true -and
            $null -eq $CurrentValue.PSObject.Properties['allowedToCreateApps'] -and
            $ExpectedValue.allowedToCreateAgentIdentityBlueprints -eq $false
        }
    }
}
