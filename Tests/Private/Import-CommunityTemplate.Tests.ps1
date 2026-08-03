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
    function Get-CIPPAzDataTableEntity {}
    function Add-CIPPAzDataTableEntity { param($Entity) $null = $Entity }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Import-CommunityTemplate.ps1')

    function Get-RepoTemplate {
        param([string]$Description = 'Description from the repo')
        [PSCustomObject]@{
            RowKey       = '7f3a91c2-4d1e-4b8a-9c3f-2e5d6a8b1f04'
            PartitionKey = 'IntuneTemplate'
            JSON         = (@{ Displayname = 'Baseline'; Description = $Description } | ConvertTo-Json -Compress)
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
