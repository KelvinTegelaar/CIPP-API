BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Add-CIPPDbItem.ps1')
}

Describe 'Add-CIPPDbItem authoritative empty collections' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Add-CIPPAzDataTableEntity {}
        Mock Remove-CIPPAzDataTableEntity {}
        Mock Get-CIPPAzDataTableEntity {
            @(
                [PSCustomObject]@{
                    PartitionKey = 'contoso.onmicrosoft.com'
                    RowKey       = 'IntuneIntents-old-policy'
                    ETag         = '*'
                    Timestamp    = [DateTimeOffset]::UtcNow.AddSeconds(-1)
                }
                [PSCustomObject]@{
                    PartitionKey = 'contoso.onmicrosoft.com'
                    RowKey       = 'IntuneIntents-Count'
                    ETag         = '*'
                    Timestamp    = [DateTimeOffset]::UtcNow.AddSeconds(-1)
                }
            )
        }
    }

    It 'clears existing rows and writes count zero when ClearOnEmpty is explicit' {
        Add-CIPPDbItem -TenantFilter 'contoso.onmicrosoft.com' -Type 'IntuneIntents' -Data @() -AddCount -ClearOnEmpty

        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            $Entity.RowKey -eq 'IntuneIntents-old-policy'
        }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            $Entity.RowKey -eq 'IntuneIntents-Count' -and $Entity.DataCount -eq 0
        }
    }

    It 'preserves existing rows for an empty collection without ClearOnEmpty' {
        Add-CIPPDbItem -TenantFilter 'contoso.onmicrosoft.com' -Type 'IntuneIntents' -Data @() -AddCount

        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0
    }

    It 'removes recently stale rows from a non-empty authoritative collection' {
        $Policy = [PSCustomObject]@{ id = 'new-policy'; displayName = 'New policy' }

        Add-CIPPDbItem -TenantFilter 'contoso.onmicrosoft.com' -Type 'IntuneIntents' -Data @($Policy) -AddCount -ClearOnEmpty

        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            $Entity.RowKey -eq 'IntuneIntents-old-policy'
        }
    }
}
