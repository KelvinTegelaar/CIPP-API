# Pester tests for Import-CommunityTemplate's direct-write (CIPP format) path.
# The write is a full replace keyed on RowKey, and the template sync reaches it automatically for
# any repo file it cannot match by name. If it proceeds when the file has not changed, a stale repo
# copy silently reverts edits made in CIPP - on a schedule, with no user action.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    # Stubs so the table calls resolve and can be mocked. Only the parameters a test actually reads
    # are declared - a mock body can only see arguments the stub itself declares, everything else
    # falls through to $args.
    function Get-CippTable { @{ Context = 'stub' } }
    function Get-CIPPTable { @{ Context = 'stub' } }
    function Get-CIPPAzDataTableEntity { param($Filter) $null = $Filter }
    function Add-CIPPAzDataTableEntity { param($Entity) $null = $Entity }
    # $null = no request context (the scheduled sync), which the importer trusts
    function Get-CippRequestAllowedPermissions { $null }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GitHub/Get-CIPPTemplateContentHash.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Import-CommunityTemplate.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaselineOutOfScopeAssignment.ps1')
    function Get-TenantGroups { @() }
    function Get-CIPPTenantLookup { @{ 'mine.onmicrosoft.com' = @{ customerId = 'tenant-1' }; 'victim.onmicrosoft.com' = @{ customerId = 'tenant-2' } } }

    function Get-RepoTemplate {
        param([string]$Description = 'Description from the repo')
        [PSCustomObject]@{
            RowKey       = '7f3a91c2-4d1e-4b8a-9c3f-2e5d6a8b1f04'
            PartitionKey = 'IntuneTemplate'
            JSON         = (@{ Displayname = 'Baseline'; Description = $Description } | ConvertTo-Json -Compress)
        }
    }

    function Get-RepoStandardsTemplate {
        param([string]$Description = 'Description from the repo')
        [PSCustomObject]@{
            RowKey       = '9a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9'
            PartitionKey = 'StandardsTemplateV2'
            JSON         = (@{ templateName = 'Baseline'; Description = $Description } | ConvertTo-Json -Compress)
        }
    }
}

Describe 'Import-CommunityTemplate direct-write path' {

    Context 'the repo file has not changed since it was last read' {
        BeforeEach {
            Mock Get-CIPPAzDataTableEntity {
                [PSCustomObject]@{
                    RowKey       = '7f3a91c2-4d1e-4b8a-9c3f-2e5d6a8b1f04'
                    PartitionKey = 'IntuneTemplate'
                    SHA          = 'abc123'
                    JSON         = (@{ Displayname = 'Baseline'; Description = 'Edited in CIPP' } | ConvertTo-Json -Compress)
                }
            }
            Mock Add-CIPPAzDataTableEntity {}
        }

        It 'does not write, so local edits survive' {
            $null = Import-CommunityTemplate -Template (Get-RepoTemplate) -SHA 'abc123' -Source 'owner/repo'
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'reports that nothing needed importing' {
            Import-CommunityTemplate -Template (Get-RepoTemplate) -SHA 'abc123' -Source 'owner/repo' |
                Should -BeLike '*already up to date*'
        }

        It 'still writes when -Force is passed, since that is an explicit overwrite' {
            $null = Import-CommunityTemplate -Template (Get-RepoTemplate) -SHA 'abc123' -Source 'owner/repo' -Force
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
        }
    }

    Context 'the repo file has changed' {
        It 'imports it' {
            Mock Get-CIPPAzDataTableEntity {
                [PSCustomObject]@{
                    RowKey       = '7f3a91c2-4d1e-4b8a-9c3f-2e5d6a8b1f04'
                    PartitionKey = 'IntuneTemplate'
                    SHA          = 'abc123'
                    JSON         = (@{ Displayname = 'Baseline' } | ConvertTo-Json -Compress)
                }
            }
            Mock Add-CIPPAzDataTableEntity {}

            $null = Import-CommunityTemplate -Template (Get-RepoTemplate) -SHA 'def456' -Source 'owner/repo'
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
        }
    }

    Context 'the template does not exist locally yet' {
        It 'imports it' {
            Mock Get-CIPPAzDataTableEntity { $null }
            Mock Add-CIPPAzDataTableEntity {}

            $null = Import-CommunityTemplate -Template (Get-RepoTemplate) -SHA 'abc123' -Source 'owner/repo'
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
        }
    }

    Context 'source path' {
        It 'stamps SourcePath when passed' {
            Mock Get-CIPPAzDataTableEntity {
                [PSCustomObject]@{
                    RowKey       = '7f3a91c2-4d1e-4b8a-9c3f-2e5d6a8b1f04'
                    PartitionKey = 'IntuneTemplate'
                    SHA          = 'abc123'
                    JSON         = (@{ Displayname = 'Baseline' } | ConvertTo-Json -Compress)
                }
            }
            $script:Written = $null
            Mock Add-CIPPAzDataTableEntity { $script:Written = $Entity }

            $null = Import-CommunityTemplate -Template (Get-RepoTemplate) -SHA 'def456' -Source 'owner/repo' -Path 'IntuneTemplate/Baseline.json'
            $script:Written.SourcePath | Should -Be 'IntuneTemplate/Baseline.json'
        }

        It 'writes no SourcePath when not passed' {
            Mock Get-CIPPAzDataTableEntity { $null }
            $script:Written = $null
            Mock Add-CIPPAzDataTableEntity { $script:Written = $Entity }

            $null = Import-CommunityTemplate -Template (Get-RepoTemplate) -SHA 'abc123' -Source 'owner/repo'
            $script:Written.PSObject.Properties.Name | Should -Not -Contain 'SourcePath'
        }
    }

    Context 'ContentHash' {
        It 'is stamped for a StandardsTemplateV2 row' {
            Mock Get-CIPPAzDataTableEntity { $null }
            $script:Written = $null
            Mock Add-CIPPAzDataTableEntity { $script:Written = $Entity }

            $null = Import-CommunityTemplate -Template (Get-RepoStandardsTemplate) -SHA 'abc123' -Source 'owner/repo'
            $script:Written.ContentHash | Should -Not -BeNullOrEmpty
            $script:Written.ContentHash | Should -Match '^[0-9a-f]{64}$'
        }

        It 'is not stamped for a non-StandardsTemplateV2 row' {
            Mock Get-CIPPAzDataTableEntity { $null }
            $script:Written = $null
            Mock Add-CIPPAzDataTableEntity { $script:Written = $Entity }

            $null = Import-CommunityTemplate -Template (Get-RepoTemplate) -SHA 'abc123' -Source 'owner/repo'
            $script:Written.PSObject.Properties.Name | Should -Not -Contain 'ContentHash'
        }
    }

    Context 'tenants named by a new standards template' {
        BeforeEach {
            Mock Get-CIPPAzDataTableEntity { $null }
            $script:Written = $null
            Mock Add-CIPPAzDataTableEntity { $script:Written = $Entity }
            $script:Template = Get-RepoStandardsTemplate
            $script:Template.JSON = (@{ templateName = 'Baseline'; tenantFilter = @(@{ value = 'victim.onmicrosoft.com'; label = 'Victim' }) } | ConvertTo-Json -Compress)
        }
        AfterEach { $script:CippAllowedTenantsStorage = $null }

        It 'refuses a restricted caller whose access does not cover them, and writes nothing' {
            $script:CippAllowedTenantsStorage = [System.Threading.AsyncLocal[object]]::new()
            $script:CippAllowedTenantsStorage.Value = @('tenant-1')
            { Import-CommunityTemplate -Template $script:Template -SHA 'abc123' -Source 'owner/repo' } | Should -Throw -ExceptionType ([System.UnauthorizedAccessException])
            $script:Written | Should -BeNullOrEmpty
        }

        It 'imports an exported file with the placeholder tenant for a restricted caller' {
            $script:CippAllowedTenantsStorage = [System.Threading.AsyncLocal[object]]::new()
            $script:CippAllowedTenantsStorage.Value = @('tenant-1')
            $script:Template.JSON = (@{ templateName = 'Baseline'; tenantFilter = @(@{ value = 'Template Tenant'; label = 'Template Tenant' }) } | ConvertTo-Json -Compress)
            $null = Import-CommunityTemplate -Template $script:Template -SHA 'abc123' -Source 'owner/repo'
            $script:Written | Should -Not -BeNullOrEmpty
        }

        It 'imports them unchanged for an unrestricted caller' {
            $null = Import-CommunityTemplate -Template $script:Template -SHA 'abc123' -Source 'owner/repo'
            ($script:Written.JSON | ConvertFrom-Json).tenantFilter.value | Should -Be 'victim.onmicrosoft.com'
        }
    }

    Context 'an existing standards template keeps its tenants, so updating it changes what they run' {
        BeforeEach {
            Mock Get-CippRequestAllowedPermissions { , @('Tenant.Standards.ReadWrite') }
            $script:Written = $null
            Mock Add-CIPPAzDataTableEntity { $script:Written = $Entity }
            $script:CippAllowedTenantsStorage = [System.Threading.AsyncLocal[object]]::new()
            $script:CippAllowedTenantsStorage.Value = @('tenant-1')
        }
        AfterEach { $script:CippAllowedTenantsStorage = $null }

        It 'refuses a restricted caller when the existing row targets tenants outside their access' {
            Mock Get-CIPPAzDataTableEntity {
                [PSCustomObject]@{
                    RowKey = '9a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9'; PartitionKey = 'StandardsTemplateV2'; SHA = 'old'
                    JSON = (@{ templateName = 'Baseline'; tenantFilter = @(@{ value = 'AllTenants'; label = 'All Tenants' }) } | ConvertTo-Json -Compress)
                }
            }
            { Import-CommunityTemplate -Template (Get-RepoStandardsTemplate) -SHA 'new' -Source 'owner/repo' -Force } | Should -Throw -ExceptionType ([System.UnauthorizedAccessException])
            $script:Written | Should -BeNullOrEmpty
        }

        It 'updates it for a restricted caller when every existing tenant is in their access' {
            Mock Get-CIPPAzDataTableEntity {
                [PSCustomObject]@{
                    RowKey = '9a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9'; PartitionKey = 'StandardsTemplateV2'; SHA = 'old'
                    JSON = (@{ templateName = 'Baseline'; tenantFilter = @(@{ value = 'mine.onmicrosoft.com'; label = 'Mine' }) } | ConvertTo-Json -Compress)
                }
            }
            $null = Import-CommunityTemplate -Template (Get-RepoStandardsTemplate) -SHA 'new' -Source 'owner/repo'
            ($script:Written.JSON | ConvertFrom-Json).tenantFilter.value | Should -Be 'mine.onmicrosoft.com'
        }
    }

    Context 'a caller without Tenant.Standards.ReadWrite' {
        BeforeEach {
            Mock Get-CippRequestAllowedPermissions { , @('CIPP.TemplateLibrary.ReadWrite') }
            $script:Written = $null
            Mock Add-CIPPAzDataTableEntity { $script:Written = $Entity }
            $script:Template = Get-RepoStandardsTemplate
            $script:Template.JSON = (@{ templateName = 'Baseline'; tenantFilter = @(@{ value = 'AllTenants'; label = 'All Tenants' }); excludedTenants = @(@{ value = 'mine.onmicrosoft.com' }) } | ConvertTo-Json -Compress)
        }

        It 'imports a new standards template unassigned, so it cannot run until someone assigns it' {
            Mock Get-CIPPAzDataTableEntity { $null }
            $null = Import-CommunityTemplate -Template $script:Template -SHA 'abc123' -Source 'owner/repo'
            $JSON = $script:Written.JSON | ConvertFrom-Json
            $JSON.tenantFilter.value | Should -Be 'Template Tenant'
            @($JSON.excludedTenants).Count | Should -Be 0
        }

        It 'cannot replace an existing standards template that is assigned to tenants' {
            Mock Get-CIPPAzDataTableEntity {
                [PSCustomObject]@{
                    RowKey = '9a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9'; PartitionKey = 'StandardsTemplateV2'; SHA = 'old'
                    JSON = (@{ templateName = 'Baseline'; tenantFilter = @(@{ value = 'mine.onmicrosoft.com'; label = 'Mine' }) } | ConvertTo-Json -Compress)
                }
            }
            { Import-CommunityTemplate -Template $script:Template -SHA 'new' -Source 'owner/repo' -Force } | Should -Throw -ExceptionType ([System.UnauthorizedAccessException])
            $script:Written | Should -BeNullOrEmpty
        }

        It 'can update an existing standards template that is still unassigned' {
            Mock Get-CIPPAzDataTableEntity {
                [PSCustomObject]@{
                    RowKey = '9a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9'; PartitionKey = 'StandardsTemplateV2'; SHA = 'old'
                    JSON = (@{ templateName = 'Baseline'; tenantFilter = @(@{ value = 'Template Tenant'; label = 'Template Tenant' }) } | ConvertTo-Json -Compress)
                }
            }
            $null = Import-CommunityTemplate -Template $script:Template -SHA 'new' -Source 'owner/repo'
            ($script:Written.JSON | ConvertFrom-Json).tenantFilter.value | Should -Be 'Template Tenant'
        }

        It 'still imports other template types' {
            Mock Get-CIPPAzDataTableEntity { $null }
            $null = Import-CommunityTemplate -Template (Get-RepoTemplate) -SHA 'abc123' -Source 'owner/repo'
            $script:Written.PartitionKey | Should -Be 'IntuneTemplate'
        }
    }

    Context 'a caller with Tenant.Standards.ReadWrite' {
        It 'keeps the file''s tenants on a new standards template' {
            Mock Get-CippRequestAllowedPermissions { , @('Tenant.Standards.ReadWrite') }
            Mock Get-CIPPAzDataTableEntity { $null }
            $script:Written = $null
            Mock Add-CIPPAzDataTableEntity { $script:Written = $Entity }
            $Template = Get-RepoStandardsTemplate
            $Template.JSON = (@{ templateName = 'Baseline'; tenantFilter = @(@{ value = 'AllTenants'; label = 'All Tenants' }) } | ConvertTo-Json -Compress)
            $null = Import-CommunityTemplate -Template $Template -SHA 'abc123' -Source 'owner/repo'
            ($script:Written.JSON | ConvertFrom-Json).tenantFilter.value | Should -Be 'AllTenants'
        }
    }

    Context 'existing row lookup' {
        It 'escapes the file''s keys in the table filter' {
            $script:Filter = $null
            Mock Get-CIPPAzDataTableEntity { $script:Filter = $Filter }
            Mock Add-CIPPAzDataTableEntity {}
            $Template = Get-RepoTemplate
            $Template.RowKey = "x' or RowKey ne 'y"
            $null = Import-CommunityTemplate -Template $Template -SHA 'abc123' -Source 'owner/repo'
            $script:Filter | Should -Be "RowKey eq 'x'' or RowKey ne ''y' and PartitionKey eq 'IntuneTemplate'"
        }
    }

    Context 'package membership' {
        It 'is kept when the repo file does not carry it' {
            Mock Get-CIPPAzDataTableEntity {
                [PSCustomObject]@{
                    RowKey       = '7f3a91c2-4d1e-4b8a-9c3f-2e5d6a8b1f04'
                    PartitionKey = 'IntuneTemplate'
                    SHA          = 'abc123'
                    Package      = 'Baseline Package'
                    JSON         = (@{ Displayname = 'Baseline' } | ConvertTo-Json -Compress)
                }
            }
            $script:Written = $null
            Mock Add-CIPPAzDataTableEntity { $script:Written = $Entity }

            $null = Import-CommunityTemplate -Template (Get-RepoTemplate) -SHA 'def456' -Source 'owner/repo'
            $script:Written.Package | Should -Be 'Baseline Package'
        }
    }
}

Describe 'Import-CommunityTemplate with a linked templates manifest' {
    It 'does not store the repo file''s LinkedTemplates manifest on the templates row' {
        Mock Get-CIPPAzDataTableEntity { $null }
        Mock Add-CIPPAzDataTableEntity {}
        $Template = Get-RepoTemplate
        $Template | Add-Member -NotePropertyName LinkedTemplates -NotePropertyValue '[{"partition":"GSAFilteringPolicyTemplate","guid":"pol-1","path":"GSAFilteringPolicyTemplate/Block_risky.json"}]'
        $null = Import-CommunityTemplate -Template $Template -SHA 'sha-1' -Source 'Org/repo'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.PSObject.Properties.Name -notcontains 'LinkedTemplates' -and $Entity.RowKey -eq '7f3a91c2-4d1e-4b8a-9c3f-2e5d6a8b1f04' }
    }
}

# A one-off import from the catalog (-ManualImport) keeps SHA and Source for the catalog's badges
# but is the user's to edit: it is marked so it is not listed as synced, and callers without the
# switch (the scheduled sync) must not overwrite it.
Describe 'Import-CommunityTemplate manual import marker' {
    BeforeAll {
        function Test-CIPPIntuneTemplate { [pscustomobject]@{ IsValid = $true } }
        function Remove-ODataProperties { param($Object) }
        function Get-RawIntuneTemplate {
            [pscustomobject]@{ '@odata.id' = 'deviceManagement/configurationPolicies/1'; name = 'OIB policy'; description = 'd'; technologies = 'mdm' }
        }
        function Get-RawCATemplate {
            [pscustomobject]@{ '@odata.type' = '#microsoft.graph.conditionalAccessPolicy'; displayName = 'CA policy'; state = 'enabled' }
        }
        $script:NoMigration = [pscustomobject]@{ objects = @() }
    }
    BeforeEach {
        $script:Written = $null
        Mock Add-CIPPAzDataTableEntity { $script:Written = $Entity }
        Mock Get-CIPPAzDataTableEntity { $null }
    }

    Context 'writing the marker' {
        It 'marks a CIPP-format Intune template' {
            $null = Import-CommunityTemplate -Template (Get-RepoTemplate) -SHA 'abc123' -Source 'owner/repo' -ManualImport
            $script:Written.ManualImport | Should -BeTrue
            $script:Written.SHA | Should -Be 'abc123'
        }

        It 'does not mark it without the switch' {
            $null = Import-CommunityTemplate -Template (Get-RepoTemplate) -SHA 'abc123' -Source 'owner/repo'
            $script:Written.PSObject.Properties.Name | Should -Not -Contain 'ManualImport'
        }

        It 'ignores a marker carried in the repo file' {
            $Template = Get-RepoTemplate
            $Template | Add-Member -NotePropertyName ManualImport -NotePropertyValue $true
            $null = Import-CommunityTemplate -Template $Template -SHA 'abc123' -Source 'owner/repo'
            $script:Written.PSObject.Properties.Name | Should -Not -Contain 'ManualImport'
        }

        It 'never marks a standards template' {
            $null = Import-CommunityTemplate -Template (Get-RepoStandardsTemplate) -SHA 'abc123' -Source 'owner/repo' -ManualImport
            $script:Written.PSObject.Properties.Name | Should -Not -Contain 'ManualImport'
        }

        It 'marks a raw Intune policy file' {
            $null = Import-CommunityTemplate -Template (Get-RawIntuneTemplate) -SHA 'abc123' -Source 'owner/repo' -ManualImport
            $script:Written.PartitionKey | Should -Be 'IntuneTemplate'
            $script:Written.ManualImport | Should -BeTrue
        }

        It 'does not mark a raw Intune policy file without the switch' {
            $null = Import-CommunityTemplate -Template (Get-RawIntuneTemplate) -SHA 'abc123' -Source 'owner/repo'
            $script:Written.PartitionKey | Should -Be 'IntuneTemplate'
            $script:Written.ContainsKey('ManualImport') | Should -BeFalse
        }

        It 'marks a raw Conditional Access policy file' {
            $null = Import-CommunityTemplate -Template (Get-RawCATemplate) -SHA 'abc123' -Source 'owner/repo' -MigrationTable $script:NoMigration -ManualImport
            $script:Written.PartitionKey | Should -Be 'CATemplate'
            $script:Written.ManualImport | Should -BeTrue
        }

        It 'does not mark a raw Conditional Access policy file without the switch' {
            $null = Import-CommunityTemplate -Template (Get-RawCATemplate) -SHA 'abc123' -Source 'owner/repo' -MigrationTable $script:NoMigration
            $script:Written.PartitionKey | Should -Be 'CATemplate'
            $script:Written.ContainsKey('ManualImport') | Should -BeFalse
        }
    }

    Context 'a manual import already exists and the repo file has changed' {
        # The CIPP-format path finds the row by RowKey, so this also covers a template renamed in CIPP
        It 'is not overwritten by a caller without the switch (CIPP format)' {
            Mock Get-CIPPAzDataTableEntity {
                [pscustomobject]@{ RowKey = '7f3a91c2-4d1e-4b8a-9c3f-2e5d6a8b1f04'; PartitionKey = 'IntuneTemplate'; SHA = 'abc123'; ManualImport = $true; JSON = '{"Displayname":"Renamed in CIPP"}' }
            }
            Import-CommunityTemplate -Template (Get-RepoTemplate) -SHA 'def456' -Source 'owner/repo' | Should -BeLike '*imported manually*'
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'is updated when the user imports it again from the catalog (CIPP format)' {
            Mock Get-CIPPAzDataTableEntity {
                [pscustomobject]@{ RowKey = '7f3a91c2-4d1e-4b8a-9c3f-2e5d6a8b1f04'; PartitionKey = 'IntuneTemplate'; SHA = 'abc123'; ManualImport = $true; JSON = '{"Displayname":"Baseline"}' }
            }
            $null = Import-CommunityTemplate -Template (Get-RepoTemplate) -SHA 'def456' -Source 'owner/repo' -ManualImport
            $script:Written.SHA | Should -Be 'def456'
            $script:Written.ManualImport | Should -BeTrue
        }

        It 'is overwritten when -Force is passed (CIPP format)' {
            Mock Get-CIPPAzDataTableEntity {
                [pscustomobject]@{ RowKey = '7f3a91c2-4d1e-4b8a-9c3f-2e5d6a8b1f04'; PartitionKey = 'IntuneTemplate'; SHA = 'abc123'; ManualImport = $true; JSON = '{"Displayname":"Baseline"}' }
            }
            $null = Import-CommunityTemplate -Template (Get-RepoTemplate) -SHA 'def456' -Source 'owner/repo' -Force
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
        }

        It 'is not overwritten by a caller without the switch (raw Intune file)' {
            Mock Get-CIPPAzDataTableEntity {
                [pscustomobject]@{ RowKey = 'row-1'; GUID = 'row-1'; PartitionKey = 'IntuneTemplate'; SHA = 'abc123'; Source = 'owner/repo'; ManualImport = $true; JSON = '{"Displayname":"OIB policy"}' }
            }
            Import-CommunityTemplate -Template (Get-RawIntuneTemplate) -SHA 'def456' -Source 'owner/repo' | Should -BeLike '*imported manually*'
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'is updated in place when the user imports it again (raw Intune file)' {
            Mock Get-CIPPAzDataTableEntity {
                [pscustomobject]@{ RowKey = 'row-1'; GUID = 'row-1'; PartitionKey = 'IntuneTemplate'; SHA = 'abc123'; Source = 'owner/repo'; ManualImport = $true; JSON = '{"Displayname":"OIB policy"}' }
            }
            $null = Import-CommunityTemplate -Template (Get-RawIntuneTemplate) -SHA 'def456' -Source 'owner/repo' -ManualImport
            $script:Written.RowKey | Should -Be 'row-1'
            $script:Written.ManualImport | Should -BeTrue
        }

        It 'is not overwritten by a caller without the switch (raw Conditional Access file)' {
            Mock Get-CIPPAzDataTableEntity {
                [pscustomobject]@{ RowKey = 'row-2'; GUID = 'row-2'; PartitionKey = 'CATemplate'; SHA = 'abc123'; Source = 'owner/repo'; ManualImport = $true; JSON = '{"displayName":"CA policy"}' }
            }
            Import-CommunityTemplate -Template (Get-RawCATemplate) -SHA 'def456' -Source 'owner/repo' -MigrationTable $script:NoMigration | Should -BeLike '*imported manually*'
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }
    }

    # Updating from the catalog is not a reason to stop syncing a template the Template Library owns
    Context 'the catalog updates a template the sync owns' {
        It 'stays unmarked (CIPP format)' {
            Mock Get-CIPPAzDataTableEntity {
                [pscustomobject]@{ RowKey = '7f3a91c2-4d1e-4b8a-9c3f-2e5d6a8b1f04'; PartitionKey = 'IntuneTemplate'; SHA = 'abc123'; JSON = '{"Displayname":"Baseline"}' }
            }
            $null = Import-CommunityTemplate -Template (Get-RepoTemplate) -SHA 'def456' -Source 'owner/repo' -ManualImport
            $script:Written.SHA | Should -Be 'def456'
            $script:Written.PSObject.Properties.Name | Should -Not -Contain 'ManualImport'
        }

        It 'stays unmarked (raw Intune file)' {
            Mock Get-CIPPAzDataTableEntity {
                [pscustomobject]@{ RowKey = 'row-1'; GUID = 'row-1'; PartitionKey = 'IntuneTemplate'; SHA = 'abc123'; Source = 'owner/repo'; JSON = '{"Displayname":"OIB policy"}' }
            }
            $null = Import-CommunityTemplate -Template (Get-RawIntuneTemplate) -SHA 'def456' -Source 'owner/repo' -ManualImport
            $script:Written.RowKey | Should -Be 'row-1'
            $script:Written.ContainsKey('ManualImport') | Should -BeFalse
        }

        It 'stays unmarked (raw Conditional Access file)' {
            Mock Get-CIPPAzDataTableEntity {
                [pscustomobject]@{ RowKey = 'row-2'; GUID = 'row-2'; PartitionKey = 'CATemplate'; SHA = 'abc123'; Source = 'owner/repo'; JSON = '{"displayName":"CA policy"}' }
            }
            $null = Import-CommunityTemplate -Template (Get-RawCATemplate) -SHA 'def456' -Source 'owner/repo' -MigrationTable $script:NoMigration -ManualImport
            $script:Written.RowKey | Should -Be 'row-2'
            $script:Written.ContainsKey('ManualImport') | Should -BeFalse
        }
    }

    # A raw file has no RowKey, so a template renamed in CIPP is only found by the repo path it came from
    Context 'a manual import was renamed in CIPP and the repo file has changed' {
        It 'is not duplicated by a caller without the switch (raw Intune file)' {
            Mock Get-CIPPAzDataTableEntity {
                [pscustomobject]@{ RowKey = 'row-1'; GUID = 'row-1'; PartitionKey = 'IntuneTemplate'; SHA = 'abc123'; Source = 'owner/repo'; SourcePath = 'a/oib.json'; ManualImport = $true; JSON = '{"Displayname":"Renamed in CIPP"}' }
            }
            Import-CommunityTemplate -Template (Get-RawIntuneTemplate) -SHA 'def456' -Source 'owner/repo' -Path 'a/oib.json' | Should -BeLike '*imported manually*'
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'is updated in place when the user imports it again (raw Intune file)' {
            Mock Get-CIPPAzDataTableEntity {
                [pscustomobject]@{ RowKey = 'row-1'; GUID = 'row-1'; PartitionKey = 'IntuneTemplate'; SHA = 'abc123'; Source = 'owner/repo'; SourcePath = 'a/oib.json'; ManualImport = $true; JSON = '{"Displayname":"Renamed in CIPP"}' }
            }
            $null = Import-CommunityTemplate -Template (Get-RawIntuneTemplate) -SHA 'def456' -Source 'owner/repo' -Path 'a/oib.json' -ManualImport
            $script:Written.RowKey | Should -Be 'row-1'
        }

        It 'does not match the same path in another repo (raw Intune file)' {
            Mock Get-CIPPAzDataTableEntity {
                [pscustomobject]@{ RowKey = 'row-1'; GUID = 'row-1'; PartitionKey = 'IntuneTemplate'; SHA = 'abc123'; Source = 'other/repo'; SourcePath = 'a/oib.json'; ManualImport = $true; JSON = '{"Displayname":"Renamed in CIPP"}' }
            }
            $null = Import-CommunityTemplate -Template (Get-RawIntuneTemplate) -SHA 'def456' -Source 'owner/repo' -Path 'a/oib.json'
            $script:Written.RowKey | Should -Not -Be 'row-1'
        }

        # Editing a synced CA template clears its SHA but keeps its path; the sync must not find it again
        It 'does not match a renamed template that an edit detached (raw Conditional Access file)' {
            Mock Get-CIPPAzDataTableEntity {
                [pscustomobject]@{ RowKey = 'row-2'; GUID = 'row-2'; PartitionKey = 'CATemplate'; SHA = ''; Source = 'owner/repo'; SourcePath = 'a/ca.json'; JSON = '{"displayName":"Renamed in CIPP"}' }
            }
            $null = Import-CommunityTemplate -Template (Get-RawCATemplate) -SHA 'def456' -Source 'owner/repo' -Path 'a/ca.json' -MigrationTable $script:NoMigration
            $script:Written.RowKey | Should -Not -Be 'row-2'
        }

        It 'is not duplicated by a caller without the switch (raw Conditional Access file)' {
            Mock Get-CIPPAzDataTableEntity {
                [pscustomobject]@{ RowKey = 'row-2'; GUID = 'row-2'; PartitionKey = 'CATemplate'; SHA = 'abc123'; Source = 'owner/repo'; SourcePath = 'a/ca.json'; ManualImport = $true; JSON = '{"displayName":"Renamed in CIPP"}' }
            }
            Import-CommunityTemplate -Template (Get-RawCATemplate) -SHA 'def456' -Source 'owner/repo' -Path 'a/ca.json' -MigrationTable $script:NoMigration | Should -BeLike '*imported manually*'
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }
    }

    Context 'a named location file' {
        It 'is refused with an explanation and writes nothing' {
            Mock Add-CIPPAzDataTableEntity {}
            $Location = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.compliantNetworkNamedLocation'; id = '3d46dbda-8382-466a-856d-eb00cbc6b910'; displayName = 'All Compliant Network locations' }
            Import-CommunityTemplate -Template $Location -SHA 'abc' -Source 'owner/repo' -Path 'Config/NamedLocations/All Compliant Network locations.json' -ManualImport |
                Should -BeLike "'All Compliant Network locations' is a named location*"
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }
    }
}
