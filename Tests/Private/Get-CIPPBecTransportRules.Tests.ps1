BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:OriginalRoot = $env:CIPPRootPath
    $env:CIPPRootPath = $RepoRoot
    function Search-CIPPBecAuditLog { param($TenantFilter, $StartDate, $EndDate, $Operations, $UserIds, $RecordType, $ObjectIds, $Anchor, $PageSize, $MaxPages) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Anchor) }
    function Get-NormalizedError { param($message) $message }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecHeuristics.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/New-CIPPBecCollectorResult.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/ConvertTo-CIPPBecHostAddress.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecTransportRules.ps1')
    $script:Heuristics = Get-CIPPBecHeuristics
    $script:Start = (Get-Date).AddDays(-7)
    $script:End = Get-Date

    function New-Record {
        param([string]$Operation, [hashtable]$Parameters, [string]$Actor = 'admin@contoso.com')
        [pscustomobject]@{
            Identity  = [guid]::NewGuid().ToString()
            Operation = $Operation
            AuditData = [pscustomobject]@{
                Operation    = $Operation
                CreationTime = '2026-08-20T09:00:00Z'
                UserId       = $Actor
                ClientIP     = '198.51.100.7'
                ObjectId     = 'Rule'
                Parameters   = @($Parameters.Keys | ForEach-Object { [pscustomobject]@{ Name = $_; Value = $Parameters[$_] } })
            }
        }
    }
}

AfterAll {
    $env:CIPPRootPath = $script:OriginalRoot
}

Describe 'Get-CIPPBecTransportRules' {
    It 'flags New/Set/Enable changes that set a diversion or suppression action and leaves the rest unflagged' {
        Mock Search-CIPPBecAuditLog {
            [pscustomobject]@{
                Records  = @(
                    (New-Record -Operation 'New-TransportRule' -Parameters @{ Name = 'Exfil'; BlindCopyTo = 'attacker@example.org'; SentTo = 'cfo@contoso.com' })
                    (New-Record -Operation 'Set-TransportRule' -Parameters @{ Identity = 'Disclaimer'; Name = 'Disclaimer'; Priority = '3' })
                    (New-Record -Operation 'Remove-TransportRule' -Parameters @{ Identity = 'Old rule'; BlindCopyTo = 'x@example.org' })
                    (New-Record -Operation 'Set-TransportRule' -Parameters @{ Identity = 'Spam'; SetSCL = '9' })
                )
                Complete = $true; Cap = $null; Pages = 1
            }
        }
        Mock New-ExoRequest { @() }
        $Result = Get-CIPPBecTransportRules -TenantFilter 'contoso.com' -StartDate $script:Start -EndDate $script:End -Heuristics $script:Heuristics
        $Result.Changes.Complete | Should -BeTrue
        $Result.Changes.Data.Count | Should -Be 4
        $Exfil = $Result.Changes.Data | Where-Object { $_.RuleName -eq 'Exfil' }
        $Exfil.Flagged | Should -BeTrue
        $Exfil.RiskyParameters | Should -Contain 'BlindCopyTo'
        $Exfil.RiskyParameters | Should -Not -Contain 'SentTo'
        $Exfil.Actor | Should -Be 'admin@contoso.com'
        $Exfil.ClientIP | Should -Be '198.51.100.7'
        ($Result.Changes.Data | Where-Object { $_.RuleName -eq 'Disclaimer' }).Flagged | Should -BeFalse
        ($Result.Changes.Data | Where-Object { $_.RuleName -eq 'Old rule' }).Flagged | Should -BeFalse -Because 'removing a rule is not persistence'
        ($Result.Changes.Data | Where-Object { $_.RuleName -eq 'Spam' }).Flagged | Should -BeTrue
        $Result.Changes.Data[0].Flagged | Should -BeTrue -Because 'flagged changes sort first'
        Should -Invoke Search-CIPPBecAuditLog -Times 1 -ParameterFilter { $RecordType -eq 'ExchangeAdmin' -and $Operations -contains 'New-TransportRule' -and $null -eq $UserIds }
    }

    It 'returns only the current rules with a diversion action, or a suppression action changed in the window, with the total rule count' {
        Mock Search-CIPPBecAuditLog { [pscustomobject]@{ Records = @(); Complete = $true; Cap = $null; Pages = 1 } }
        Mock New-ExoRequest {
            @(
                [pscustomobject]@{ Identity = 'Exfil'; Guid = 'g1'; Name = 'Exfil'; State = 'Enabled'; Mode = 'Enforce'; Priority = 0; WhenChanged = (Get-Date).AddDays(-1).ToString('o'); Description = 'If the message is sent to cfo@contoso.com, Blind carbon copy (Bcc) the message to attacker@example.org'; BlindCopyTo = @('attacker@example.org'); RedirectMessageTo = @(); DeleteMessage = $false }
                [pscustomobject]@{ Identity = 'Disclaimer'; Guid = 'g2'; Name = 'Disclaimer'; State = 'Enabled'; Mode = 'Enforce'; Priority = 1; WhenChanged = '2025-01-01T00:00:00Z'; Description = 'Append a disclaimer'; BlindCopyTo = @(); RedirectMessageTo = @(); DeleteMessage = $false; ApplyHtmlDisclaimerText = '<div>External</div>' }
                [pscustomobject]@{ Identity = 'Junk'; Guid = 'g3'; Name = 'Junk'; State = 'Disabled'; Mode = 'Audit'; Priority = 2; WhenChanged = '2025-01-01T00:00:00Z'; Description = 'Quarantine the message'; BlindCopyTo = @(); RedirectMessageTo = @(); DeleteMessage = $false; Quarantine = $false }
                [pscustomobject]@{ Identity = 'Plain'; Guid = 'g4'; Name = 'Plain'; State = 'Disabled'; Mode = 'Enforce'; Priority = 3; WhenChanged = '2025-01-01T00:00:00Z'; Description = 'Prepend the subject'; BlindCopyTo = @(); RedirectMessageTo = @(); DeleteMessage = $false }
                [pscustomobject]@{ Identity = 'OldDelete'; Guid = 'g5'; Name = 'OldDelete'; State = 'Enabled'; Mode = 'Enforce'; Priority = 4; WhenChanged = '2025-01-01T00:00:00Z'; Description = 'Delete the message without notifying anyone'; BlindCopyTo = @(); RedirectMessageTo = @(); DeleteMessage = $true; RemoveHeader = 'Disposition-Notification-To' }
                [pscustomobject]@{ Identity = 'RecentDelete'; Guid = 'g6'; Name = 'RecentDelete'; State = 'Enabled'; Mode = 'Enforce'; Priority = 5; WhenChanged = (Get-Date).AddHours(-3).ToString('o'); Description = 'Delete the message without notifying anyone'; BlindCopyTo = @(); RedirectMessageTo = @(); DeleteMessage = 'True' }
            )
        }
        $Result = Get-CIPPBecTransportRules -TenantFilter 'contoso.com' -StartDate $script:Start -EndDate $script:End -Heuristics $script:Heuristics
        $Result.Flagged.Data.Name | Should -Be @('Exfil', 'RecentDelete') -Because 'rules changed in the window sort first and only action-bearing rules are flagged'
        $Exfil = $Result.Flagged.Data | Where-Object { $_.Name -eq 'Exfil' }
        $Exfil.RiskReasons | Should -Contain 'BlindCopyTo = attacker@example.org'
        $Exfil.RiskReasons | Should -Contain 'Description mentions a routing or disposition action'
        $Exfil.ChangedInWindow | Should -BeTrue
        $Recent = $Result.Flagged.Data | Where-Object { $_.Name -eq 'RecentDelete' }
        $Recent.RiskReasons | Should -Contain 'DeleteMessage = True'
        $Recent.RiskReasons | Should -Contain 'Changed within the investigation window'
        $Result.Flagged.Data.Name | Should -Not -Contain 'OldDelete' -Because 'a long-standing delete/header rule is admin hygiene, not persistence'
        $Result.Flagged.Data.Name | Should -Not -Contain 'Junk' -Because 'a description alone never flags a rule'
        $Result.Flagged.Data.Name | Should -Not -Contain 'Disclaimer'
        $Result.Flagged.Data.Name | Should -Not -Contain 'Plain'
    }

    It 'reports each half independently when the other fails' {
        Mock Search-CIPPBecAuditLog { throw 'UAL unavailable' }
        Mock New-ExoRequest { @([pscustomobject]@{ Identity = 'r'; Guid = 'g'; Name = 'r'; State = 'Enabled'; Mode = 'Enforce'; Description = 'redirect the message'; RedirectMessageTo = @('x@example.org') }) }
        $Result = Get-CIPPBecTransportRules -TenantFilter 'contoso.com' -StartDate $script:Start -EndDate $script:End -Heuristics $script:Heuristics
        $Result.Changes.Complete | Should -BeFalse
        $Result.Changes.Error | Should -Match 'UAL unavailable'
        $Result.Flagged.Complete | Should -BeTrue
        $Result.Flagged.Data.Count | Should -Be 1

        Mock Search-CIPPBecAuditLog { [pscustomobject]@{ Records = @(); Complete = $true; Cap = $null; Pages = 1 } }
        Mock New-ExoRequest { throw 'EXO down' }
        $Result = Get-CIPPBecTransportRules -TenantFilter 'contoso.com' -StartDate $script:Start -EndDate $script:End -Heuristics $script:Heuristics
        $Result.Changes.Complete | Should -BeTrue
        $Result.Flagged.Complete | Should -BeFalse
        $Result.Flagged.Error | Should -Match 'EXO down'
    }
}
