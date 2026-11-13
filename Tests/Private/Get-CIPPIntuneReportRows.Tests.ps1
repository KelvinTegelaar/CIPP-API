# Pester tests for Get-CIPPIntuneReportRows
# Pins the schema+values row build and the top/skip paging of Intune report actions

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPIntuneReportRows.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Get-CIPPIntuneReportRows.ps1 under Modules/' }

    function New-GraphPOSTRequest {
        param($uri, $tenantid, $body)
        $script:posts += , ($body | ConvertFrom-Json)
        $Page = $script:pages[$script:posts.Count - 1]
        if ($script:posts.Count -eq 1) { return ($Page | ConvertTo-Json -Depth 10) }
        $Page
    }

    . $FunctionPath
}

Describe 'Get-CIPPIntuneReportRows' {
    BeforeEach {
        $script:posts = @()
        $script:pages = @(
            @{ TotalRowCount = 3; Schema = @(@{ Column = 'PolicyId' }, @{ Column = 'PolicyName' }); Values = @(@('p1', 'One'), @('p2', 'Two')) }
            @{ TotalRowCount = 3; Schema = @(@{ Column = 'PolicyId' }, @{ Column = 'PolicyName' }); Values = @(, @('p3', 'Three')) }
        )
    }

    It 'builds one object per row keyed by column name and walks every page' {
        $rows = Get-CIPPIntuneReportRows -TenantFilter 'contoso.onmicrosoft.com' -Uri 'https://graph.microsoft.com/beta/deviceManagement/reports/getX' -Filter "(PolicyId eq 'p')" -PageSize 2

        @($rows).Count | Should -Be 3
        $rows[0].PolicyId | Should -Be 'p1'
        $rows[2].PolicyName | Should -Be 'Three'
        $posts.Count | Should -Be 2
        $posts[0].skip | Should -Be 0
        $posts[1].skip | Should -Be 2
        $posts[0].top | Should -Be 2
        $posts[0].filter | Should -Be "(PolicyId eq 'p')"
        $posts[0].orderBy | Should -Be @('PolicyName')
    }

    It 'stops after a short page' {
        $script:pages = @(@{ TotalRowCount = 1; Schema = @(@{ Column = 'A' }); Values = @(, @('x')) })

        $rows = Get-CIPPIntuneReportRows -TenantFilter 't' -Uri 'u' -PageSize 2

        @($rows).Count | Should -Be 1
        $posts.Count | Should -Be 1
    }
}
