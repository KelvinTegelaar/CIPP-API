# Pester tests for Get-CIPPPagedTableRows
# Validates the cross-partition range-scan pager: row-count paging independent of how many
# partitions the data spans, continuation token round-trips (including escaping), plan
# membership filtering, and the query-count economy that motivated the range design.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    # Stub so Pester's Mock has a command to replace.
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property, $First) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPPagedTableRows.ps1')

    # In-memory table emulation for the filter shapes the pager emits (PK/RK ranges, the
    # OR resume clause, ordinal ordering, -First). Test keys never contain quotes.
    function Select-FakeRows {
        param([object[]]$Rows, [string]$Filter, $First)
        $PkGe = if ($Filter -match "PartitionKey ge '([^']*)'") { $Matches[1] } else { $null }
        $PkLe = if ($Filter -match "PartitionKey le '([^']*)'") { $Matches[1] } else { $null }
        $RkGe = if ($Filter -match "RowKey ge '([^']*)'") { $Matches[1] } else { $null }
        $RkLt = if ($Filter -match "RowKey lt '([^']*)'") { $Matches[1] } else { $null }
        $Resume = if ($Filter -match "\(\(PartitionKey gt '([^']*)'\) or \(PartitionKey eq '[^']*' and RowKey gt '([^']*)'\)\)") {
            @{ Pk = $Matches[1]; Rk = $Matches[2] }
        } else { $null }
        $Out = @($Rows | Where-Object {
                $Row = $_
                $Keep = (-not $PkGe -or [string]::CompareOrdinal($Row.PartitionKey, $PkGe) -ge 0) -and
                        (-not $PkLe -or [string]::CompareOrdinal($Row.PartitionKey, $PkLe) -le 0) -and
                        (-not $RkGe -or [string]::CompareOrdinal($Row.RowKey, $RkGe) -ge 0) -and
                        (-not $RkLt -or [string]::CompareOrdinal($Row.RowKey, $RkLt) -lt 0)
                if ($Keep -and $Resume) {
                    $Keep = ([string]::CompareOrdinal($Row.PartitionKey, $Resume.Pk) -gt 0) -or
                            ($Row.PartitionKey -ceq $Resume.Pk -and [string]::CompareOrdinal($Row.RowKey, $Resume.Rk) -gt 0)
                }
                $Keep
            } | Sort-Object -Property @{ Expression = { $_.PartitionKey }; Ascending = $true }, @{ Expression = { $_.RowKey }; Ascending = $true })
        if ($First) { $Out = @($Out | Select-Object -First ([int]$First)) }
        $Out
    }

    function New-FakeRow {
        param([string]$Pk, [string]$Rk)
        [PSCustomObject]@{ PartitionKey = $Pk; RowKey = $Rk; Data = "$Pk/$Rk" }
    }
}

Describe 'Get-CIPPPagedTableRows' {
    BeforeEach {
        $script:FakeRows = @()
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            Select-FakeRows -Rows $script:FakeRows -Filter $Filter -First $First
        }
    }

    It 'walks partitions in ordinal order and completes with a null token when everything fits' {
        $script:FakeRows = @(
            New-FakeRow 'tenantB' 'Guests-2'
            New-FakeRow 'tenantA' 'Guests-1'
            New-FakeRow 'tenantB' 'Guests-1'
        )

        $Page = Get-CIPPPagedTableRows -Table @{ Context = 'fake' } -PartitionKeys @('tenantA', 'tenantB') -PageSize 100

        $Page.Rows | Should -HaveCount 3
        $Page.Rows[0].Data | Should -Be 'tenantA/Guests-1'
        $Page.Rows[1].Data | Should -Be 'tenantB/Guests-1'
        $Page.Rows[2].Data | Should -Be 'tenantB/Guests-2'
        $Page.NextToken | Should -BeNullOrEmpty
    }

    It 'pages many small partitions in one page with a bounded query count' {
        # The complaint this design answers: row-count paging must not degrade with the
        # partition count. 60 one-row tenants fit one 100-row page in a couple of queries.
        $script:FakeRows = foreach ($i in 1..60) {
            New-FakeRow ('tenant{0:D3}' -f $i) 'Users-1'
        }
        $Plan = @(1..60 | ForEach-Object { 'tenant{0:D3}' -f $_ })

        $Page = Get-CIPPPagedTableRows -Table @{ Context = 'fake' } -PartitionKeys $Plan -PageSize 100

        $Page.Rows | Should -HaveCount 60
        $Page.NextToken | Should -BeNullOrEmpty
        Should -Invoke Get-CIPPAzDataTableEntity -Times 2 -Exactly
    }

    It 'returns full coverage without duplicates when paging with continuation tokens' {
        $script:FakeRows = foreach ($Tenant in 'tenantA', 'tenantB') {
            foreach ($i in 1..5) { New-FakeRow $Tenant ('Users-{0:D2}' -f $i) }
        }

        $Collected = [System.Collections.Generic.List[string]]::new()
        $Token = $null
        $Pages = 0
        do {
            $Page = Get-CIPPPagedTableRows -Table @{ Context = 'fake' } -PartitionKeys @('tenantA', 'tenantB') -PageSize 3 -ContinuationToken $Token
            foreach ($Row in $Page.Rows) { $Collected.Add($Row.Data) }
            $Token = $Page.NextToken
            $Pages++
        } while ($Token -and $Pages -lt 20)

        $Pages | Should -BeLessThan 20
        $Collected | Should -HaveCount 10
        ($Collected | Sort-Object -Unique) | Should -HaveCount 10
        $Collected[0] | Should -Be 'tenantA/Users-01'
        $Collected[-1] | Should -Be 'tenantB/Users-05'
    }

    It 'applies the RowKey range bounds' {
        $script:FakeRows = @(
            New-FakeRow 'tenantA' 'Groups-1'
            New-FakeRow 'tenantA' 'Guests-1'
            New-FakeRow 'tenantA' 'Guests-Count'
            New-FakeRow 'tenantA' 'Mailboxes-1'
        )

        $Page = Get-CIPPPagedTableRows -Table @{ Context = 'fake' } -PartitionKeys @('tenantA') -RowKeyGe 'Guests-' -RowKeyLt 'Guests.' -PageSize 100

        # Only the Guests-* range: no Groups, no Mailboxes. The count marker is inside the
        # range by design; callers remove it.
        $Page.Rows.RowKey | Should -Be @('Guests-1', 'Guests-Count')
    }

    It 'drops rows from partitions outside the plan but keeps advancing the cursor' {
        # gone.example sits ordinally between the plan tenants and floods the range with
        # rows; they must be filtered out without stalling or re-reading.
        $script:FakeRows = @(New-FakeRow 'aaa.example' 'Users-1') +
        @(foreach ($i in 1..6) { New-FakeRow 'gone.example' ('Users-{0}' -f $i) }) +
        @(New-FakeRow 'zzz.example' 'Users-1')

        $Collected = [System.Collections.Generic.List[string]]::new()
        $Token = $null
        $Pages = 0
        do {
            $Page = Get-CIPPPagedTableRows -Table @{ Context = 'fake' } -PartitionKeys @('aaa.example', 'zzz.example') -PageSize 3 -ContinuationToken $Token
            foreach ($Row in $Page.Rows) { $Collected.Add($Row.Data) }
            $Token = $Page.NextToken
            $Pages++
        } while ($Token -and $Pages -lt 10)

        $Collected | Should -Be @('aaa.example/Users-1', 'zzz.example/Users-1')
    }

    It 'ends a short page with a token when MaxQueries runs out before PageSize' {
        # Every chunk is full of non-plan rows, so kept rows stay short of PageSize and
        # the safety bound has to end the page with resumable progress.
        $script:FakeRows = @(foreach ($i in 1..9) { New-FakeRow 'gone.example' ('Users-{0}' -f $i) }) +
        @(New-FakeRow 'zzz.example' 'Users-1')

        $Page1 = Get-CIPPPagedTableRows -Table @{ Context = 'fake' } -PartitionKeys @('aaa.example', 'zzz.example') -PageSize 3 -MaxQueries 2
        $Page1.Rows | Should -HaveCount 0
        $Page1.NextToken | Should -Not -BeNullOrEmpty

        # Chaining the short pages still reaches everything exactly once.
        $Collected = [System.Collections.Generic.List[string]]::new()
        $Token = $Page1.NextToken
        $Pages = 1
        do {
            $Page = Get-CIPPPagedTableRows -Table @{ Context = 'fake' } -PartitionKeys @('aaa.example', 'zzz.example') -PageSize 3 -MaxQueries 2 -ContinuationToken $Token
            foreach ($Row in $Page.Rows) { $Collected.Add($Row.Data) }
            $Token = $Page.NextToken
            $Pages++
        } while ($Token -and $Pages -lt 10)

        $Pages | Should -BeLessThan 10
        $Collected | Should -Be @('zzz.example/Users-1')
    }

    It 'round-trips tokens whose keys contain the separator and non-ASCII characters' {
        $script:FakeRows = @(
            New-FakeRow 'tenant|pipe' 'Users-aä'
            New-FakeRow 'tenant|pipe' 'Users-b'
        )

        $Page1 = Get-CIPPPagedTableRows -Table @{ Context = 'fake' } -PartitionKeys @('tenant|pipe') -PageSize 1
        $Page1.Rows | Should -HaveCount 1
        $Page1.Rows[0].RowKey | Should -Be 'Users-aä'
        $Page1.NextToken | Should -Not -BeNullOrEmpty

        $Page2 = Get-CIPPPagedTableRows -Table @{ Context = 'fake' } -PartitionKeys @('tenant|pipe') -PageSize 1 -ContinuationToken $Page1.NextToken
        $Page2.Rows | Should -HaveCount 1
        $Page2.Rows[0].RowKey | Should -Be 'Users-b'
    }

    It 'ANDs extra filter clauses onto every query' {
        $script:FakeRows = @(New-FakeRow 'tenantA' 'Users-1')

        $null = Get-CIPPPagedTableRows -Table @{ Context = 'fake' } -PartitionKeys @('tenantA') -PageSize 10 -ExtraFilterClauses @("Severity eq 'Error'")

        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $Filter -like "*and Severity eq 'Error'" }
    }

    It 'returns an empty completed page for an empty partition plan' {
        $Page = Get-CIPPPagedTableRows -Table @{ Context = 'fake' } -PartitionKeys @() -PageSize 10

        $Page.Rows | Should -HaveCount 0
        $Page.NextToken | Should -BeNullOrEmpty
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0
    }
}
