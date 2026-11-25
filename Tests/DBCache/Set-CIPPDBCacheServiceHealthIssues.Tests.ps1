# Set-CIPPDBCacheServiceHealthIssues also writes CippServiceHealth: each issue body once (rewritten only when
# Microsoft changed it), one link per tenant and issue, and a Collected marker, and drops the tenant's stale links.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Get-CIPPTable { param($tablename) @{ Context = 'ctx' } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Remove-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheServiceHealthIssues.ps1')
}

Describe 'Set-CIPPDBCacheServiceHealthIssues CippServiceHealth rows' {
    BeforeEach {
        $script:Written = $null
        $script:Removed = $null
        Mock Add-CIPPDbItem {}
        Mock New-GraphGetRequest {
            [pscustomobject]@{ id = 'EX1'; isResolved = $false; lastModifiedDateTime = '2026-11-20T10:00:00Z'; details = @([pscustomobject]@{ name = 'Workload'; value = 'Exchange' }) }
            [pscustomobject]@{ id = 'SP9'; isResolved = $true; lastModifiedDateTime = '2026-11-01T10:00:00Z'; details = @() }
        }
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -eq "PartitionKey eq 'Issue'") { [pscustomobject]@{ PartitionKey = 'Issue'; RowKey = 'SP9'; LastModified = '2026-11-01T10:00:00Z' } }
            if ($Filter -like "PartitionKey eq 'Tenant'*") {
                [pscustomobject]@{ PartitionKey = 'Tenant'; RowKey = 'contoso.com|EX1' }
                [pscustomobject]@{ PartitionKey = 'Tenant'; RowKey = 'contoso.com|OLD1' }
            }
        }
        Mock Add-CIPPAzDataTableEntity { $script:Written = @($Entity) }
        Mock Remove-AzDataTableEntity { $script:Removed = @($Entity) }

        Set-CIPPDBCacheServiceHealthIssues -TenantFilter 'contoso.com'
    }

    It 'rewrites only the issue bodies Microsoft changed' {
        $Bodies = @($script:Written | Where-Object { $_.PartitionKey -eq 'Issue' })
        $Bodies.RowKey | Should -Be @('EX1')
        $Bodies[0].isResolved | Should -BeFalse
        $Bodies[0].LastModified | Should -Be '2026-11-20T10:00:00Z'
        ([CIPP.CippJson]::ConvertFromJson($Bodies[0].Data, $null)).id | Should -Be 'EX1'
    }

    It 'links the tenant to every issue it reports, with its details and resolved state' {
        $Links = @($script:Written | Where-Object { $_.PartitionKey -eq 'Tenant' })
        $Links.RowKey | Should -Be @('contoso.com|EX1', 'contoso.com|SP9')
        ($Links | Where-Object IssueId -EQ 'SP9').isResolved | Should -BeTrue
        ([CIPP.CippJson]::ConvertFromJson(($Links | Where-Object IssueId -EQ 'EX1').Details, $null))[0].value | Should -Be 'Exchange'
    }

    It 'marks the tenant collected and removes links to issues it no longer reports' {
        @($script:Written | Where-Object { $_.PartitionKey -eq 'Collected' }).RowKey | Should -Be @('contoso.com')
        $script:Removed.RowKey | Should -Be @('contoso.com|OLD1')
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Filter -eq "PartitionKey eq 'Tenant' and RowKey ge 'contoso.com|' and RowKey lt 'contoso.com}'" }
    }
}
