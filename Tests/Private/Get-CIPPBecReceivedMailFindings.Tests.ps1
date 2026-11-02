BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:OriginalRoot = $env:CIPPRootPath
    $env:CIPPRootPath = $RepoRoot
    function Get-CIPPBecMessageTrace { param($TenantFilter, $SenderAddress, $RecipientAddress, $StartDate, $EndDate, $Anchor, $PageSize, $MaxPages) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $noPagination, [switch]$Stream) }
    function Get-NormalizedError { param($message) $message }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Get-CIPPLevenshteinDistance.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecHeuristics.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/New-CIPPBecCollectorResult.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecReceivedMailFindings.ps1')
    $script:Heuristics = Get-CIPPBecHeuristics

    function New-Row {
        param([string]$Sender, [string]$Subject, [int]$Index = 1)
        [pscustomobject]@{
            MessageTraceId   = "trace-$Index"
            SenderAddress    = $Sender
            RecipientAddress = 'victim@contoso.com'
            Subject          = $Subject
            Status           = 'Delivered'
            Received         = '2026-08-20T12:00:00Z'
            Size             = 1024
            FromIP           = '203.0.113.9'
        }
    }
    $script:Start = (Get-Date).AddDays(-7)
    $script:End = Get-Date
}

AfterAll {
    $env:CIPPRootPath = $script:OriginalRoot
}

Describe 'Get-CIPPBecReceivedMailFindings' {
    It 'flags look-alike sender domains within one or two edits of an accepted domain, never the accepted domain itself' {
        Mock Get-CIPPBecMessageTrace {
            [pscustomobject]@{
                Rows     = @(
                    (New-Row -Sender 'billing@contos0.com' -Subject 'Your statement' -Index 1)
                    (New-Row -Sender 'it@c0nt0so.com' -Subject 'Hello' -Index 2)
                    (New-Row -Sender 'friend@contoso.com' -Subject 'Lunch' -Index 3)
                    (New-Row -Sender 'news@example.org' -Subject 'Weekly digest' -Index 4)
                    (New-Row -Sender 'spoof@contoso-secure-login.com' -Subject 'Hi' -Index 5)
                )
                Complete = $true; Cap = $null; Pages = 1
            }
        }
        $Result = Get-CIPPBecReceivedMailFindings -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -StartDate $script:Start -EndDate $script:End -Heuristics $script:Heuristics -AcceptedDomains @('contoso.com', 'contoso.onmicrosoft.com')
        $Typos = @($Result.Findings.Data | Where-Object { $_.FindingType -eq 'PossibleTyposquat' })
        $Typos.SenderDomain | Should -Contain 'contos0.com'
        $Typos.SenderDomain | Should -Contain 'c0nt0so.com'
        $Typos.SenderDomain | Should -Not -Contain 'contoso.com'
        $Typos.SenderDomain | Should -Not -Contain 'example.org'
        $Typos.SenderDomain | Should -Not -Contain 'contoso-secure-login.com'
        ($Typos | Where-Object { $_.SenderDomain -eq 'contos0.com' }).Distance | Should -Be 1
        ($Typos | Where-Object { $_.SenderDomain -eq 'c0nt0so.com' }).ComparedDomain | Should -Be 'contoso.com'
        $Result.Findings.Summary.TyposquatDomains | Should -Contain 'contos0.com'
        $Result.Findings.Complete | Should -BeTrue
    }

    It 'names the phishing-subject pattern that matched and keeps keyword-only hits at Low' {
        Mock Get-CIPPBecMessageTrace {
            [pscustomobject]@{
                Rows     = @(
                    (New-Row -Sender 'a@example.org' -Subject 'URGENT action is required on your account' -Index 1)
                    (New-Row -Sender 'b@example.org' -Subject 'Please verify your account today' -Index 2)
                    (New-Row -Sender 'c@example.org' -Subject 'Suspended: access to your mailbox' -Index 3)
                    (New-Row -Sender 'd@example.org' -Subject 'You are our lottery winner' -Index 4)
                    (New-Row -Sender 'e@example.org' -Subject 'Invoice 4471 attached' -Index 5)
                    (New-Row -Sender 'f@example.org' -Subject 'New password policy' -Index 6)
                    (New-Row -Sender 'g@example.org' -Subject 'Lunch on Friday?' -Index 7)
                )
                Complete = $true; Cap = $null; Pages = 1
            }
        }
        $Result = Get-CIPPBecReceivedMailFindings -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -StartDate $script:Start -EndDate $script:End -Heuristics $script:Heuristics -AcceptedDomains @('contoso.com')
        $Patterns = @($Result.Findings.Data | Where-Object { $_.FindingType -eq 'SubjectPattern' })
        $Patterns.Reason | Should -Contain 'Urgent action language'
        $Patterns.Reason | Should -Contain 'Account verification language'
        $Patterns.Reason | Should -Contain 'Account suspension language'
        $Patterns.Reason | Should -Contain 'Prize or lottery language'
        $Patterns.Reason | Should -Contain 'Invoice or payment language'
        $Keyword = @($Result.Findings.Data | Where-Object { $_.FindingType -eq 'SubjectKeyword' })
        $Keyword.Count | Should -Be 1
        $Keyword[0].Subject | Should -Be 'New password policy'
        $Keyword[0].Severity | Should -Be 'Low'
        ($Result.Findings.Data | Where-Object { $_.Subject -eq 'Lunch on Friday?' }) | Should -BeNullOrEmpty
    }

    It 'never stores message content - findings carry trace metadata only' {
        Mock Get-CIPPBecMessageTrace { [pscustomobject]@{ Rows = @((New-Row -Sender 'x@contos0.com' -Subject 'Invoice')); Complete = $true; Cap = $null; Pages = 1 } }
        $Result = Get-CIPPBecReceivedMailFindings -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -StartDate $script:Start -EndDate $script:End -Heuristics $script:Heuristics -AcceptedDomains @('contoso.com')
        $Names = @($Result.Findings.Data[0].PSObject.Properties.Name)
        $Names | Should -Not -Contain 'Body'
        $Names | Should -Not -Contain 'Attachments'
        $Names | Should -Contain 'MessageTraceId'
    }

    It 'propagates a capped trace as partial' {
        Mock Get-CIPPBecMessageTrace { [pscustomobject]@{ Rows = @((New-Row -Sender 'x@example.org' -Subject 'hi')); Complete = $false; Cap = '5 pages of 5000 rows'; Pages = 5 } }
        $Result = Get-CIPPBecReceivedMailFindings -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -StartDate $script:Start -EndDate $script:End -Heuristics $script:Heuristics -AcceptedDomains @('contoso.com')
        $Result.Findings.Complete | Should -BeFalse
        $Result.Findings.Cap | Should -Be '5 pages of 5000 rows'
    }

    It 'reports a trace failure as an error, not as a clean mailbox' {
        Mock Get-CIPPBecMessageTrace { throw 'EXO is down' }
        $Result = Get-CIPPBecReceivedMailFindings -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -StartDate $script:Start -EndDate $script:End -Heuristics $script:Heuristics -AcceptedDomains @('contoso.com')
        $Result.Findings.Complete | Should -BeFalse
        $Result.Findings.Error | Should -Match 'EXO is down'
        $Result.Findings.Data.Count | Should -Be 0
    }

    Context 'Defender analysed-email metadata' {
        BeforeEach {
            Mock Get-CIPPBecMessageTrace { [pscustomobject]@{ Rows = @(); Complete = $true; Cap = $null; Pages = 1 } }
        }

        It 'is skipped without -IncludeDefender' {
            Mock New-GraphGetRequest { throw 'Defender must not be queried' }
            $Result = Get-CIPPBecReceivedMailFindings -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -StartDate $script:Start -EndDate $script:End -Heuristics $script:Heuristics
            $Result.Defender.Available | Should -BeFalse
            # Not querying Defender is a skip (the run's licence preflight found no Defender P2), not a
            # clean pass: it must never read as complete.
            $Result.Defender.Complete | Should -BeFalse
            $Result.Defender.Skipped | Should -BeTrue
            $Result.Defender.Requirement | Should -Match 'Defender for Office 365 Plan 2'
            Should -Invoke New-GraphGetRequest -Times 0
        }

        It 'reads the window tenant-wide, keeps this mailbox''s threat-classified rows and marks delivered ones' {
            # shape as returned by beta/security/collaboration/analyzedEmails (loggedDateTime, latestDelivery{action,location})
            Mock New-GraphGetRequest {
                @(
                    [pscustomobject]@{ networkMessageId = 'a'; loggedDateTime = '2026-08-20T10:00:00Z'; recipientEmailAddress = 'victim@contoso.com'; subject = 'Phish'; threatTypes = @('phish'); latestDelivery = [pscustomobject]@{ action = 'delivered'; location = 'inbox' }; originalDelivery = [pscustomobject]@{ action = 'delivered'; location = 'inbox' }; senderDetail = [pscustomobject]@{ fromAddress = 'bad@example.org'; ipv4 = '198.51.100.9' } }
                    [pscustomobject]@{ networkMessageId = 'b'; loggedDateTime = '2026-08-20T11:00:00Z'; recipientEmailAddress = 'VICTIM@contoso.com'; subject = 'Blocked'; threatTypes = @('malware'); latestDelivery = [pscustomobject]@{ action = 'blocked'; location = 'quarantine' }; senderDetail = [pscustomobject]@{ fromAddress = 'bad2@example.org' } }
                    [pscustomobject]@{ networkMessageId = 'c'; loggedDateTime = '2026-08-20T12:00:00Z'; recipientEmailAddress = 'victim@contoso.com'; subject = 'Clean'; threatTypes = @('none'); latestDelivery = [pscustomobject]@{ action = 'delivered'; location = 'inbox' }; senderDetail = [pscustomobject]@{ fromAddress = 'ok@example.org' } }
                    [pscustomobject]@{ networkMessageId = 'd'; loggedDateTime = '2026-08-20T13:00:00Z'; recipientEmailAddress = 'someone.else@contoso.com'; subject = 'Phish for someone else'; threatTypes = @('phish'); latestDelivery = [pscustomobject]@{ action = 'delivered'; location = 'inbox' }; senderDetail = [pscustomobject]@{ fromAddress = 'bad@example.org' } }
                )
            }
            $Result = Get-CIPPBecReceivedMailFindings -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -StartDate $script:Start -EndDate $script:End -Heuristics $script:Heuristics -IncludeDefender
            $Result.Defender.Available | Should -BeTrue
            $Result.Defender.Complete | Should -BeTrue
            $Result.Defender.Data.Count | Should -Be 2
            $Result.Defender.Data.NetworkMessageId | Should -Not -Contain 'd' -Because 'other recipients are matched out client-side'
            $A = $Result.Defender.Data | Where-Object { $_.NetworkMessageId -eq 'a' }
            $A.Delivered | Should -BeTrue
            $A.ReceivedDateTime | Should -Be '2026-08-20T10:00:00Z'
            $A.SenderIP | Should -Be '198.51.100.9'
            $A.LatestDeliveryLocation | Should -Be 'inbox'
            ($Result.Defender.Data | Where-Object { $_.NetworkMessageId -eq 'b' }).Delivered | Should -BeFalse
            $Result.Defender.AnalyzedCount | Should -Be 3 -Because 'three of the four analysed messages were addressed to this mailbox'
            # the service rejects $filter on the recipient, so the request carries the window only and is streamed page by page
            Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter { $uri -like '*security/collaboration/analyzedEmails?startTime=*' -and $uri -notlike '*$filter*' -and $uri -like '*$top=1000*' -and $AsApp -eq $true -and $Stream -eq $true -and $noPagination -ne $true }
        }

        It 'reports a permission error as incomplete with the PermissionError flag, never as "no phishing"' {
            Mock New-GraphGetRequest { throw 'Authorization_RequestDenied: Insufficient privileges to complete the operation.' }
            $Result = Get-CIPPBecReceivedMailFindings -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -StartDate $script:Start -EndDate $script:End -Heuristics $script:Heuristics -IncludeDefender
            $Result.Defender.Complete | Should -BeFalse
            $Result.Defender.Available | Should -BeFalse
            $Result.Defender.PermissionError | Should -BeTrue
            $Result.Defender.Error | Should -Match 'unavailable'
        }
    }
}
