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
