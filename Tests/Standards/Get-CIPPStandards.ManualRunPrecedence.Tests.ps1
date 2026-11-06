# Running one standards template by hand must still respect the three-tier merge: a standard that a more specific
# template overrides for a tenant (for example set to Report only) must not be run from the broader template.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $ModulesRoot = Join-Path $BackendRoot 'Modules'
    function Resolve-CippFunctionFile {
        param([string]$Name)
        Get-ChildItem -Path $ModulesRoot -Recurse -Filter $Name -File | Select-Object -First 1 -ExpandProperty FullName
    }

    function Get-TenantGroups { [CmdletBinding()] param($GroupId) }
    function Get-CippTable { [CmdletBinding()] param($tablename) }
    function Get-CIPPAzDataTableEntity { [CmdletBinding()] param($Filter) }
    function Get-Tenants { [CmdletBinding()] param($TenantFilter, [switch]$IncludeErrors, [switch]$IncludeAll) }

    . (Resolve-CippFunctionFile -Name 'Merge-CippStandards.ps1')
    . (Resolve-CippFunctionFile -Name 'Convert-SingleStandardObject.ps1')
    . (Resolve-CippFunctionFile -Name 'ConvertTo-CippStandardObject.ps1')
    . (Resolve-CippFunctionFile -Name 'Get-CIPPStandards.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    function New-ForwardingTemplateRow {
        param([string]$Guid, [object[]]$TenantFilter, [string[]]$Actions, [int]$Minute, [switch]$ForwardingOnly)
        [pscustomobject]@{
            RowKey    = $Guid
            TimeStamp = ([datetime]'2026-01-01').AddMinutes($Minute)
            JSON      = (@{
                    GUID         = $Guid
                    templateName = "Template $Guid"
                    runManually  = $false
                    tenantFilter = $TenantFilter
                    standards    = if ($ForwardingOnly) {
                        @{ EXODisableAutoForwarding = @{ action = @($Actions | ForEach-Object { @{ label = $_; value = $_ } }) } }
                    } else {
                        @{
                            EXODisableAutoForwarding = @{ action = @($Actions | ForEach-Object { @{ label = $_; value = $_ } }) }
                            DisableBasicAuthSMTP     = @{ action = @(@{ label = 'Remediate'; value = 'Remediate' }) }
                        }
                    }
                } | ConvertTo-Json -Depth 12)
        }
    }
}

Describe 'Get-CIPPStandards manual run of a single template' {
    BeforeEach {
        Mock Get-TenantGroups { @([pscustomobject]@{ Id = 'group-1'; Members = @([pscustomobject]@{ defaultDomainName = $script:Tenant }) }) }
        Mock Get-CippTable { @{} }
        Mock Get-Tenants { @([pscustomobject]@{ defaultDomainName = $script:Tenant; customerId = '1111' }) }
        Mock Get-CIPPAzDataTableEntity { param($Filter) if ($Filter -match 'StandardsTemplateV2') { $script:Rows } else { @() } }
    }

    Context 'a <Tier> template remediates forwarding and a tenant-specific template reports it' -ForEach @(
        @{ Tier = 'AllTenants'; Filter = @(@{ type = 'Tenant'; value = 'AllTenants' }) }
        @{ Tier = 'group'; Filter = @(@{ type = 'Group'; value = 'group-1'; label = 'Business' }) }
    ) {
        BeforeEach {
            $script:Rows = @(
                New-ForwardingTemplateRow -Guid 'business' -TenantFilter $Filter -Actions 'Remediate', 'Report' -Minute 1
                New-ForwardingTemplateRow -Guid 'customer' -TenantFilter @(@{ type = 'Tenant'; value = $script:Tenant }) -Actions 'Report' -Minute 2 -ForwardingOnly
            )
        }

        It 'leaves the overridden standard out of a manual run of the broader template' {
            $Result = @(Get-CIPPStandards -TenantFilter $script:Tenant -TemplateId 'business')
            $Result.Standard | Should -Not -Contain 'EXODisableAutoForwarding'
        }

        It 'still runs the standards the broader template wins' {
            $Result = @(Get-CIPPStandards -TenantFilter $script:Tenant -TemplateId 'business')
            $Result.Standard | Should -Contain 'DisableBasicAuthSMTP'
        }

        It 'runs the override as report only from the tenant-specific template' {
            $Result = @(Get-CIPPStandards -TenantFilter $script:Tenant -TemplateId 'customer')
            $Forwarding = @($Result.Where({ $_.Standard -eq 'EXODisableAutoForwarding' }))[0]
            $Forwarding.Settings.report | Should -BeTrue
            $Forwarding.Settings.remediate | Should -BeFalse
        }
    }
}
