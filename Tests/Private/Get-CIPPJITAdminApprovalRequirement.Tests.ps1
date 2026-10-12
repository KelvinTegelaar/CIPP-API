BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value }
    function Get-Tenants { param([string]$TenantFilter, [switch]$IncludeErrors) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPJITAdminApprovalRequirement.ps1')

    $GlobalAdmin = '62e90394-69f5-4237-9190-012177145e10'
    function New-Settings {
        param([bool]$RequireApproval = $true, [string]$TriggerRoles = '[]', [string]$Tenants = '[]')
        [pscustomobject]@{ RequireApproval = $RequireApproval; ApprovalTriggerRoles = $TriggerRoles; ApprovalTenants = $Tenants; ApproverRoles = '["admin","Approvers"]'; RequiredApprovals = 2 }
    }
}

Describe 'Get-CIPPJITAdminApprovalRequirement' {
    It 'requires nothing when approval is off' {
        Mock Get-CIPPAzDataTableEntity { New-Settings -RequireApproval $false }
        Get-CIPPJITAdminApprovalRequirement -Roles @($GlobalAdmin) | Should -BeNullOrEmpty
    }

    It 'requires approval for every request when no trigger roles are set' {
        Mock Get-CIPPAzDataTableEntity { New-Settings }
        $Requirement = Get-CIPPJITAdminApprovalRequirement -Roles @()
        $Requirement.RequiredApprovals | Should -Be 2
        $Requirement.ApproverRoles | Should -Be @('admin', 'Approvers')
    }

    It 'only requires approval when a trigger role is requested' {
        Mock Get-CIPPAzDataTableEntity { New-Settings -TriggerRoles "[{`"label`":`"Global Administrator`",`"value`":`"$GlobalAdmin`"}]" }
        Get-CIPPJITAdminApprovalRequirement -Roles @('other-role') | Should -BeNullOrEmpty
        Get-CIPPJITAdminApprovalRequirement -Roles @('other-role', $GlobalAdmin) | Should -Not -BeNullOrEmpty
    }

    Context 'tenant scope' {
        BeforeAll {
            # Entries store the customer id; Other is an entry saved by domain
            $script:SelectedTenants = '[{"label":"Contoso (contoso.com)","value":"contoso-id","type":"Tenant"},{"label":"EU","value":"group-eu","type":"Group"}]'
        }
        BeforeEach {
            $script:ApprovalTenants = $script:SelectedTenants
            Mock Get-CIPPAzDataTableEntity {
                switch ($TableName) {
                    'TenantGroups' { if ($Filter -match "RowKey eq 'group-eu'") { [pscustomobject]@{ RowKey = 'group-eu' } } }
                    # Fabrikam's membership row is keyed by customer id, Northwind's by its default domain (pre-migration row)
                    'TenantGroupMembers' {
                        if ($Filter -match "GroupId eq 'group-eu'" -and $Filter -match "customerId eq '(fabrikam-id|northwind.com)'") { [pscustomobject]@{ GroupId = 'group-eu'; customerId = $Matches[1] } }
                    }
                    default { New-Settings -Tenants $script:ApprovalTenants -TriggerRoles $script:TriggerRoles }
                }
            }
            $script:TriggerRoles = '[]'
            Mock Get-Tenants {
                @(
                    [pscustomobject]@{ customerId = 'contoso-id'; defaultDomainName = 'contoso.com'; initialDomainName = 'contoso.onmicrosoft.com' }
                    [pscustomobject]@{ customerId = 'fabrikam-id'; defaultDomainName = 'fabrikam.com'; initialDomainName = 'fabrikam.onmicrosoft.com' }
                    [pscustomobject]@{ customerId = 'northwind-id'; defaultDomainName = 'northwind.com'; initialDomainName = 'northwind.onmicrosoft.com' }
                    [pscustomobject]@{ customerId = 'other-id'; defaultDomainName = 'other.onmicrosoft.com'; initialDomainName = 'other.onmicrosoft.com' }
                ).Where({ $TenantFilter -in @($_.customerId, $_.defaultDomainName, $_.initialDomainName) })
            }
        }

        It 'requires approval in every tenant when no tenants are selected' {
            $script:ApprovalTenants = '[]'
            Get-CIPPJITAdminApprovalRequirement -Roles @($GlobalAdmin) -TenantFilter 'other.onmicrosoft.com' | Should -Not -BeNullOrEmpty
            Should -Invoke Get-Tenants -Times 0
        }

        It 'matches a selected tenant however the request addresses it' {
            'contoso-id', 'contoso.com', 'contoso.onmicrosoft.com' | ForEach-Object {
                Get-CIPPJITAdminApprovalRequirement -Roles @($GlobalAdmin) -TenantFilter $_ | Should -Not -BeNullOrEmpty
            }
        }

        It 'matches a tenant entry saved by domain' {
            $script:ApprovalTenants = '[{"label":"Other","value":"other.onmicrosoft.com","type":"Tenant"}]'
            Get-CIPPJITAdminApprovalRequirement -Roles @($GlobalAdmin) -TenantFilter 'other-id' | Should -Not -BeNullOrEmpty
        }

        It 'reads group members from storage, whatever groups the caller can see' {
            Get-CIPPJITAdminApprovalRequirement -Roles @($GlobalAdmin) -TenantFilter 'fabrikam.onmicrosoft.com' | Should -Not -BeNullOrEmpty
            Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'TenantGroupMembers' }
        }

        It 'matches a group member row keyed by default domain' {
            Get-CIPPJITAdminApprovalRequirement -Roles @($GlobalAdmin) -TenantFilter 'northwind-id' | Should -Not -BeNullOrEmpty
        }

        It 'requires nothing outside the selected tenants and groups' {
            Get-CIPPJITAdminApprovalRequirement -Roles @($GlobalAdmin) -TenantFilter 'other.onmicrosoft.com' | Should -BeNullOrEmpty
            Get-CIPPJITAdminApprovalRequirement -Roles @($GlobalAdmin) -TenantFilter 'other-id' | Should -BeNullOrEmpty
        }

        It 'keeps approval required when a selected group no longer exists' {
            $script:ApprovalTenants = '[{"label":"Gone","value":"group-gone","type":"Group"}]'
            Get-CIPPJITAdminApprovalRequirement -Roles @($GlobalAdmin) -TenantFilter 'other.onmicrosoft.com' | Should -Not -BeNullOrEmpty
        }

        It 'keeps approval required when the tenant is missing, does not resolve, or the lookup fails' {
            Get-CIPPJITAdminApprovalRequirement -Roles @($GlobalAdmin) | Should -Not -BeNullOrEmpty
            Get-CIPPJITAdminApprovalRequirement -Roles @($GlobalAdmin) -TenantFilter 'unknown.onmicrosoft.com' | Should -Not -BeNullOrEmpty
            Mock Get-Tenants { throw 'GDAP lookup failed' }
            Get-CIPPJITAdminApprovalRequirement -Roles @($GlobalAdmin) -TenantFilter 'other.onmicrosoft.com' 3>$null | Should -Not -BeNullOrEmpty
        }

        It 'skips the tenant lookup when no trigger role is requested' {
            $script:TriggerRoles = "[{`"label`":`"Global Administrator`",`"value`":`"$GlobalAdmin`"}]"
            Get-CIPPJITAdminApprovalRequirement -Roles @('other-role') -TenantFilter 'contoso.com' | Should -BeNullOrEmpty
            Should -Invoke Get-Tenants -Times 0
        }
    }
}
