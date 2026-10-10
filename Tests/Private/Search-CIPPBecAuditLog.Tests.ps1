BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Anchor) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Search-CIPPBecAuditLog.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/ConvertTo-CIPPBecHostAddress.ps1')

    function New-Page {
        param([int]$From, [int]$Count, [int]$Total, [string]$Prefix = 'id')
        foreach ($i in $From..($From + $Count - 1)) {
            [pscustomobject]@{
                Identity     = "$Prefix$i"
                CreationDate = '2026-08-20T10:00:00Z'
                Operations   = 'New-InboxRule'
                UserIds      = 'user@contoso.com'
                RecordType   = 'ExchangeAdmin'
                ResultIndex  = $i
                ResultCount  = $Total
                AuditData    = "{`"Operation`":`"New-InboxRule`",`"Id`":$i}"
            }
        }
    }
    $script:Start = (Get-Date).AddDays(-7)
    $script:End = Get-Date
}

Describe 'Search-CIPPBecAuditLog' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[object]]::new()
    }

    It 'returns a short page as complete with parsed AuditData' {
        Mock New-ExoRequest { $script:Calls.Add($cmdParams); New-Page -From 1 -Count 3 -Total 3 }
        $Result = Search-CIPPBecAuditLog -TenantFilter 'contoso.com' -StartDate $script:Start -EndDate $script:End -Operations @('New-InboxRule') -UserIds @('user@contoso.com') -PageSize 5000
        $Result.Complete | Should -BeTrue
        $Result.Pages | Should -Be 1
        $Result.Cap | Should -BeNullOrEmpty
        $Result.Records.Count | Should -Be 3
        $Result.Records[0].AuditData.Id | Should -Be 1
        $Result.Records[0].Operation | Should -Be 'New-InboxRule'
    }

    It 'sends ReturnLargeSet, ResultSize and an array UserIds with a stable session id' {
        Mock New-ExoRequest { $script:Calls.Add($cmdParams); New-Page -From 1 -Count 1 -Total 1 }
        $null = Search-CIPPBecAuditLog -TenantFilter 'contoso.com' -StartDate $script:Start -EndDate $script:End -Operations @('A') -UserIds 'user@contoso.com' -PageSize 100
        $script:Calls[0].SessionCommand | Should -Be 'ReturnLargeSet'
        $script:Calls[0].ResultSize | Should -Be 100
        $script:Calls[0].UserIds -is [array] | Should -BeTrue
        $script:Calls[0].SessionId | Should -Match '^CIPP-BEC-'
    }

    It 'follows full pages until the service reports the last row and reuses the session id' {
        Mock New-ExoRequest {
            $script:Calls.Add($cmdParams)
            switch ($script:Calls.Count) {
                1 { New-Page -From 1 -Count 4 -Total 10 }
                2 { New-Page -From 5 -Count 4 -Total 10 }
                default { New-Page -From 9 -Count 2 -Total 10 }
            }
        }
        $Result = Search-CIPPBecAuditLog -TenantFilter 'contoso.com' -StartDate $script:Start -EndDate $script:End -PageSize 4 -MaxPages 10
        $Result.Complete | Should -BeTrue
        $Result.Pages | Should -Be 3
        $Result.Records.Count | Should -Be 10
        ($script:Calls | ForEach-Object { $_.SessionId } | Select-Object -Unique).Count | Should -Be 1
    }

    It 'stops at an exact multiple of the page size when ResultIndex reaches ResultCount' {
        Mock New-ExoRequest { $script:Calls.Add($cmdParams); New-Page -From 1 -Count 4 -Total 4 }
        $Result = Search-CIPPBecAuditLog -TenantFilter 'contoso.com' -StartDate $script:Start -EndDate $script:End -PageSize 4 -MaxPages 10
        $Result.Complete | Should -BeTrue
        $Result.Pages | Should -Be 1
        $Result.Records.Count | Should -Be 4
    }

    It 'reports partial results when a leaf slice (below MinSliceMinutes) still hits the page cap' {
        # A window smaller than MinSliceMinutes cannot be bisected further, so it caps as before.
        Mock New-ExoRequest { $script:Calls.Add($cmdParams); New-Page -From (($script:Calls.Count - 1) * 4 + 1) -Count 4 -Total 100 }
        $Result = Search-CIPPBecAuditLog -TenantFilter 'contoso.com' -StartDate $script:End.AddMinutes(-30) -EndDate $script:End -PageSize 4 -MaxPages 2 -MinSliceMinutes 60
        $Result.Complete | Should -BeFalse
        $Result.Pages | Should -Be 2
        $Result.Cap | Should -Match '2 pages'
        $Result.Records.Count | Should -Be 8
    }

    It 'bisects a page-capped window on time and covers each half with its own budget' {
        # Full pages for a window wider than one slice => the top window caps; each 60-minute half comes
        # back short => complete. Coverage is by time, so the whole window is searched despite the cap.
        Mock New-ExoRequest {
            $script:Calls.Add($cmdParams)
            $Minutes = [int](New-TimeSpan -Start $cmdParams.StartDate -End $cmdParams.EndDate).TotalMinutes
            # Unique ids per call so a wide window caps (rather than stalling on a repeated page).
            if ($Minutes -gt 61) { New-Page -From ($script:Calls.Count * 4) -Count 4 -Total 100 }
            else { New-Page -From (5000 + 10 * $script:Calls.Count) -Count 2 -Total 2 }
        }
        $Result = Search-CIPPBecAuditLog -TenantFilter 'contoso.com' -StartDate $script:End.AddMinutes(-120) -EndDate $script:End -PageSize 4 -MaxPages 2 -MinSliceMinutes 60
        $Result.Complete | Should -BeTrue
        $Result.Cap | Should -BeNullOrEmpty
        $Result.Records.Count | Should -Be 4
        # the top window paged twice (capped), then each of the two 60-minute halves was searched
        @($script:Calls | Where-Object { [int](New-TimeSpan -Start $_.StartDate -End $_.EndDate).TotalMinutes -le 61 }).Count | Should -Be 2
    }

    It 'terminates and reports incomplete when even the smallest slice stays dense' {
        Mock New-ExoRequest { $script:Calls.Add($cmdParams); New-Page -From (($script:Calls.Count - 1) * 4 + 1) -Count 4 -Total 100 }
        $Result = Search-CIPPBecAuditLog -TenantFilter 'contoso.com' -StartDate $script:End.AddMinutes(-240) -EndDate $script:End -PageSize 4 -MaxPages 2 -MinSliceMinutes 60
        $Result.Complete | Should -BeFalse
        # bounded recursion: a 240-minute window bisected to 60-minute leaves is a handful of slices, not unbounded
        $script:Calls.Count | Should -BeLessThan 40
    }

    It 'keeps the pages already collected when a later page errors, and reports it partial' {
        Mock New-ExoRequest {
            $script:Calls.Add($cmdParams)
            if ($script:Calls.Count -eq 1) { New-Page -From 1 -Count 4 -Total 100 }
            else { throw 'EXO transient failure' }
        }
        $Result = Search-CIPPBecAuditLog -TenantFilter 'contoso.com' -StartDate $script:End.AddMinutes(-30) -EndDate $script:End -PageSize 4 -MaxPages 5 -MinSliceMinutes 60
        $Result.Complete | Should -BeFalse
        $Result.Records.Count | Should -Be 4
        $Result.Cap | Should -Match 'page error'
        $Result.Cap | Should -Match 'EXO transient failure'
    }

    It 'stops and reports partial results when the service replays the same page' {
        Mock New-ExoRequest { $script:Calls.Add($cmdParams); New-Page -From 1 -Count 4 -Total 100 }
        $Result = Search-CIPPBecAuditLog -TenantFilter 'contoso.com' -StartDate $script:Start -EndDate $script:End -PageSize 4 -MaxPages 10
        $Result.Complete | Should -BeFalse
        $Result.Cap | Should -Match 'stalled'
        $Result.Records.Count | Should -Be 4
        $Result.Pages | Should -Be 2
    }

    It 'returns an empty, complete result when the search has no hits' {
        Mock New-ExoRequest { $script:Calls.Add($cmdParams); $null }
        $Result = Search-CIPPBecAuditLog -TenantFilter 'contoso.com' -StartDate $script:Start -EndDate $script:End -Operations @('X')
        $Result.Complete | Should -BeTrue
        $Result.Records.Count | Should -Be 0
    }

    It 'keeps a record whose AuditData is not JSON instead of failing the search' {
        Mock New-ExoRequest { $script:Calls.Add($cmdParams); [pscustomobject]@{ Identity = 'x'; Operations = 'Op'; AuditData = 'not json'; ResultIndex = 1; ResultCount = 1 } }
        $Result = Search-CIPPBecAuditLog -TenantFilter 'contoso.com' -StartDate $script:Start -EndDate $script:End
        $Result.Records.Count | Should -Be 1
        $Result.Records[0].AuditData | Should -BeNullOrEmpty
        $Result.Records[0].Operation | Should -Be 'Op'
    }

    It 'sends bare client addresses and free text, and keeps them on every bisected slice' {
        Mock New-ExoRequest {
            $script:Calls.Add($cmdParams)
            $Minutes = [int](New-TimeSpan -Start $cmdParams.StartDate -End $cmdParams.EndDate).TotalMinutes
            if ($Minutes -gt 61) { New-Page -From ($script:Calls.Count * 4) -Count 4 -Total 100 }
            else { New-Page -From (5000 + 10 * $script:Calls.Count) -Count 2 -Total 2 }
        }
        $null = Search-CIPPBecAuditLog -TenantFilter 'contoso.com' -StartDate $script:End.AddMinutes(-120) -EndDate $script:End -PageSize 4 -MaxPages 2 -MinSliceMinutes 60 -IPAddresses @('198.51.100.7:51234', '[2001:db8::1]:443', '198.51.100.7') -FreeText 'FORM1'
        $script:Calls.Count | Should -BeGreaterThan 2
        foreach ($Call in $script:Calls) {
            @($Call.IPAddresses) | Should -Be @('198.51.100.7', '2001:db8::1') -Because 'the service rejects an address with a port'
            $Call.FreeText | Should -Be 'FORM1'
        }
    }
}
