BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Anchor) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecMessageTrace.ps1')

    function New-TraceRow {
        param([int]$Index, [string]$Recipient = "r$Index@example.com")
        [pscustomobject]@{
            MessageTraceId   = "trace-$Index"
            RecipientAddress = $Recipient
            SenderAddress    = 'user@contoso.com'
            Subject          = "Subject $Index"
            Status           = 'Delivered'
            Received         = (Get-Date '2026-08-20T12:00:00Z').AddMinutes(-$Index).ToString('o')
            FromIP           = '203.0.113.5'
        }
    }
    $script:Start = (Get-Date).AddDays(-7)
    $script:End = Get-Date
}

Describe 'Get-CIPPBecMessageTrace' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[object]]::new()
    }

    It 'requires a sender or a recipient' {
        { Get-CIPPBecMessageTrace -TenantFilter 'contoso.com' -StartDate $script:Start -EndDate $script:End } | Should -Throw
    }

    It 'returns a short page as complete and passes ResultSize and the address' {
        Mock New-ExoRequest { $script:Calls.Add($cmdParams); 1..2 | ForEach-Object { New-TraceRow -Index $_ } }
        $Result = Get-CIPPBecMessageTrace -TenantFilter 'contoso.com' -SenderAddress 'user@contoso.com' -StartDate $script:Start -EndDate $script:End -PageSize 5
        $Result.Complete | Should -BeTrue
        $Result.Rows.Count | Should -Be 2
        $Result.Pages | Should -Be 1
        $script:Calls[0].ResultSize | Should -Be 5
        $script:Calls[0].SenderAddress | Should -Be 'user@contoso.com'
        $script:Calls[0].Keys | Should -Not -Contain 'RecipientAddress'
    }

    It 'walks the cursor using the last row''s Received as EndDate and its recipient as StartingRecipientAddress' {
        Mock New-ExoRequest {
            $script:Calls.Add(($cmdParams.Clone()))
            if ($script:Calls.Count -eq 1) { 1..2 | ForEach-Object { New-TraceRow -Index $_ } } else { @(New-TraceRow -Index 3) }
        }
        $Result = Get-CIPPBecMessageTrace -TenantFilter 'contoso.com' -RecipientAddress 'user@contoso.com' -StartDate $script:Start -EndDate $script:End -PageSize 2
        $Result.Complete | Should -BeTrue
        $Result.Rows.Count | Should -Be 3
        $Result.Pages | Should -Be 2
        $script:Calls[1].StartingRecipientAddress | Should -Be 'r2@example.com'
        # the cursor is sent as a sortable UTC string, the same shape the window bounds use
        $script:Calls[1].EndDate | Should -Be ((Get-Date '2026-08-20T12:00:00Z').ToUniversalTime().AddMinutes(-2).ToString('s'))
    }

    It 'walks every page until a short page ends the window - there is no page ceiling' {
        Mock New-ExoRequest { $script:Calls.Add($cmdParams); $Base = ($script:Calls.Count - 1) * 2; if ($script:Calls.Count -le 7) { 1..2 | ForEach-Object { New-TraceRow -Index ($Base + $_) } } else { New-TraceRow -Index ($Base + 1) } }
        $Result = Get-CIPPBecMessageTrace -TenantFilter 'contoso.com' -SenderAddress 'user@contoso.com' -StartDate $script:Start -EndDate $script:End -PageSize 2
        $Result.Complete | Should -BeTrue
        $Result.Pages | Should -Be 8
        $Result.Rows.Count | Should -Be 15
        $Result.Cap | Should -BeNullOrEmpty
    }

    It 'stops and reports partial results when the cursor does not advance' {
        Mock New-ExoRequest { $script:Calls.Add($cmdParams); 1..2 | ForEach-Object { New-TraceRow -Index $_ } }
        $Result = Get-CIPPBecMessageTrace -TenantFilter 'contoso.com' -SenderAddress 'user@contoso.com' -StartDate $script:Start -EndDate $script:End -PageSize 2
        $Result.Complete | Should -BeFalse
        $Result.Cap | Should -Match 'stalled'
        $Result.Rows.Count | Should -Be 2
    }

    It 'de-duplicates rows that appear on two pages' {
        Mock New-ExoRequest {
            $script:Calls.Add($cmdParams)
            if ($script:Calls.Count -eq 1) { 1..2 | ForEach-Object { New-TraceRow -Index $_ } } else { @((New-TraceRow -Index 2), (New-TraceRow -Index 3)) }
        }
        $Result = Get-CIPPBecMessageTrace -TenantFilter 'contoso.com' -SenderAddress 'user@contoso.com' -StartDate $script:Start -EndDate $script:End -PageSize 2
        $Result.Rows.Count | Should -Be 3
        $Result.Complete | Should -BeFalse -Because 'a full second page with one duplicate is still a full page that hit the cursor; the walk continues until a short page'
    }
}
