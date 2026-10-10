# Pester tests for the fixed-report tree builders: each composes @{ Blocks; Variables } from shaped
# sample data, the grade on the cover matches the tree's own scoring, and the tree renders to a PDF.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Bin = Join-Path $RepoRoot 'Shared/CIPPSharp/bin'
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Core.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Pdf.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'CIPPSharp.dll'))

    $Reporting = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Directory -Filter 'Reporting' | Select-Object -First 1
    Get-ChildItem -Path $Reporting.FullName -Filter '*.ps1' | ForEach-Object { . $_.FullName }
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'ConvertTo-CippReportPdf.ps1' | Select-Object -First 1 -ExpandProperty FullName)
    function Get-CIPPBrandingSettings { @{ colour = '#F77F00' } }

    function Test-Report($Report, [string]$Label) {
        $Report.Blocks.Count | Should -BeGreaterThan 0
        $Report.Variables.coverlabel | Should -Be $Label
        $Bytes = ConvertTo-CippReportPdf -Blocks $Report.Blocks -Variables $Report.Variables -TenantName 'Contoso' -ReportName 'T'
        [System.Text.Encoding]::ASCII.GetString($Bytes[0..4]) | Should -Be '%PDF-'
    }
}

Describe 'Report tree builders' {
    It 'Sharing: grades exposure from the summary and renders' {
        $r = Build-CippSharingReportTree -Data @{
            TenantName    = 'Contoso'
            summary       = @{ totalLinks = 4; itemsShared = 3; externalRecipients = 1; anonymousEditLinks = 1; neverExpiringAnonymous = 1 }
            links         = @(@{ fileName = 'a.docx'; siteName = 'S'; classification = 'Anonymous'; roles = @('write'); itemType = 'File' })
            topRecipients = @(@{ recipient = 'x@example.com'; links = 1 })
            topLibraries  = @()
        }
        $r.Variables.covermetanote | Should -Be 'Sharing exposure: High'
        Test-Report $r 'Data Sharing Review'
    }

    It 'Permissions: a lone detached library is Low exposure and renders' {
        $r = Build-CippPermissionsReportTree -Data @{
            TenantName  = 'Contoso'
            summary     = @{ uniquePermissionLibraries = 1; sitesScanned = 2; librariesScanned = 3; totalAssignments = 5 }
            assignments = @(@{ principalId = 'p1'; scope = 'Library'; siteName = 'S'; libraryTitle = 'Docs'; title = 'Bob'; permissionLevel = 'Edit'; principalType = 'User' })
        }
        $r.Variables.covermetanote | Should -Be 'Permission exposure: Low'
        Test-Report $r 'Access Review'
    }

    It 'MailFlow: sums the dispositions, grades hygiene and renders' {
        $r = Build-CippMailFlowReportTree -Data @{
            TenantName = 'Contoso'; days = 7
            totals     = @{ GoodMail = 90; EmailPhish = 10 }
            daily      = @(@{ date = '2026-09-01'; GoodMail = 90; EmailPhish = 10 })
            topSenders = @(@{ name = 'a@contoso.com'; count = 5 })
        }
        $r.Variables.covermeta | Should -Be ("100 messages {0} 90% delivered {0} 10 threats caught" -f [char]0x00B7)
        $r.Variables.covermetanote | Should -Be 'Mail hygiene: Attention Needed'
        Test-Report $r 'Email Traffic Review'
    }

    It 'MailFlow: an empty window (no rows at all) still renders, with empty charts' {
        $r = Build-CippMailFlowReportTree -Data @{ TenantName = 'Contoso' }
        $r.Variables.covermetanote | Should -Be 'Mail hygiene: Good'
        Test-Report $r 'Email Traffic Review'
    }

    It 'Permissions and ShadowAI: word their empty tables the way the client does' {
        $Permissions = Build-CippPermissionsReportTree -Data @{ TenantName = 'Contoso'; summary = @{}; assignments = @() }
        @($Permissions.Blocks | Where-Object type -EQ 'richtable').emptyText | Should -Be @('No libraries hold their own permissions.')
        $ShadowAI = Build-CippShadowAIReportTree -Data @{ TenantName = 'Contoso'; summary = @{}; detectedApps = @(); consentedApps = @(); topTools = @(); byRisk = @() }
        @($ShadowAI.Blocks | Where-Object type -EQ 'richtable').emptyText | Should -Be @(
            'No AI software was detected on managed devices during the last inventory sync.'
            'No AI applications were found in Entra ID.'
        )
    }

    It 'ShadowAI: merges sanctioned tools across both sources and renders' {
        $r = Build-CippShadowAIReportTree -Data @{
            TenantName    = 'Contoso'
            summary       = @{ aiToolsDetected = 2 }
            detectedApps  = @(@{ aiTool = 'ChatGPT'; vendor = 'OpenAI'; category = 'Chat'; status = 'Sanctioned'; deviceCount = 3; risk = 'High' })
            consentedApps = @(@{ aiTool = 'ChatGPT'; vendor = 'OpenAI'; category = 'Chat'; status = 'Sanctioned'; activeUsersLast7Days = 5; risk = 'High' })
            topTools      = @(); byRisk = @(@{ risk = 'High'; tools = 1 })
        }
        $Sanctioned = $r.Blocks | Where-Object { $_.type -eq 'richtable' -and $_.rows[0].tool -eq 'ChatGPT' -and $_.rows[0].users } | Select-Object -First 1
        $Sanctioned.rows[0].devices | Should -Be '3'
        $Sanctioned.rows[0].users | Should -Be '5'
        Test-Report $r 'AI Risk Assessment'
    }

    It 'Executive: composes every section from shaped data and renders' {
        $r = Build-CippExecutiveReportTree -Data @{
            TenantName       = 'Contoso'
            UserStats        = @{ licensedUsers = 10; unlicensedUsers = 1; guests = 2; globalAdmins = 1; permanentGlobalAdmins = 1; eligibleGlobalAdmins = 0; pimCapable = $true }
            SecureScore      = @{ currentScore = 50; maxScore = 100; percentageCurrent = 50; percentageVsSimilar = 40; percentageVsAllTenants = 45; trend = @(@{ label = 'Sep 1'; value = 50 }) }
            Licenses         = @(@{ name = 'E3'; used = '5'; available = '1'; total = '6' })
            Devices          = @(@{ name = 'PC1'; os = 'Windows'; compliance = 'compliant'; compliant = $true; lastSync = 'Sep 1, 2026'; encrypted = $true })
            CAPolicies       = @(@{ name = 'Require MFA'; state = 'enabled'; controls = @('mfa'); controlsText = 'MFA'; applications = 'All' })
            SecurityControls = @(@{ name = 'MFA'; description = 'd'; tags = 't'; status = 'Compliant' })
        }
        @($r.Blocks | Where-Object { $_.type -eq 'hero' }).Count | Should -Be 5
        $r.Variables.covertenant | Should -Be 'Contoso'
        Test-Report $r 'SECURITY ASSESSMENT'
    }

    It 'BEC: renders the server-computed threat level, names the user on the cover and renders' {
        # The threat level is computed server-side (Get-CIPPBecScore) and stored on the run; the builder
        # renders that stored Score rather than scoring the findings itself.
        $r = Build-CippBecReportTree -TenantName 'Contoso' -UserData @{ displayName = 'Alice'; userPrincipalName = 'alice@contoso.com' } -BecData @{
            ExtractedAt         = '2026-09-01T00:00:00Z'
            Score               = @{ Value = 19; Level = 'High' }
            NewRules            = @(@{ Name = 'Hide'; MoveToFolder = 'RSS Subscriptions' })
            SentMessageAnalysis = @{ Flagged = $true; Bursts = @(@{ MessageCount = 40; RecipientCount = 40; WindowStart = '2026-09-01T09:00:00Z'; TopSubject = 'Invoice' }) }
            LocationAnalysis    = @{ UsageLocation = 'AU' }
        }
        ($r.Blocks | Where-Object { $_.type -eq 'alertbox' -and $_.title -like 'Threat Assessment:*' }).title | Should -Be 'Threat Assessment: High (score 19)'
        $r.Variables.covertenant | Should -Be 'Alice'
        $r.Variables.footerlabel | Should -Be 'Contoso - BEC Analysis Report for Alice'
        Test-Report $r 'Security Incident Report'
    }

    It 'BEC: carries the attacker addresses, what was done from them and the reach beyond the account, condensed in the summary' {
        $Sample = Get-Content (Join-Path $RepoRoot 'Config/ReportSamples/bec.json') -Raw | ConvertFrom-Json
        $Full = Build-CippBecReportTree -TenantName 'Contoso' -UserData $Sample.userData -BecData $Sample.becData
        $Summary = Build-CippBecReportTree -TenantName 'Contoso' -UserData $Sample.userData -BecData $Sample.becData -Variant summary
        $Found = @(($Summary.Blocks | Where-Object { $_.type -eq 'richbullets' } | Select-Object -First 1).items.text)
        $Found | Should -Contain "1 network address in NG was identified as the attacker's; from there the attacker opened 1 email, sent 1 email, opened 1 file (1 download)."
        ($Found -like 'The attack reached beyond this account: 1 other account signed into or used from the same addresses (finance.lead@example.com)*').Count | Should -Be 1
        $Actions = @(($Summary.Blocks | Where-Object { $_.type -eq 'richtable' -and $_.columns[0].header -eq 'Priority' }).rows)
        ($Actions | Where-Object { $_.text -like 'Secure the 1 other account(s)*' }).tag | Should -Be 'Critical'
        ($Actions | Where-Object { $_.text -like 'Remove the 1 Microsoft Form(s)*' }).text | Should -Match 'Microsoft Defender alert'
        $Objectives = ($Summary.Blocks | Where-Object { $_.type -eq 'progress' } | Select-Object -First 1).items
        $Objectives[0].label | Should -Be 'Attacker IPs & activity'
        $Timeline = @(($Summary.Blocks | Where-Object { $_.type -eq 'richtable' -and $_.columns[1].header -eq 'Event' }).rows)
        ($Timeline | Where-Object { $_.event -eq '1 message(s) opened' }).detail | Should -Be 'Invoice 4471 - updated bank details - 198.51.100.23'
        ($Summary.Blocks | Where-Object { $_.type -eq 'page' -and $_.title -eq 'Attacker Addresses & Activity' }) | Should -BeNullOrEmpty -Because 'the C-suite summary stops after the executive lead'
        ($Full.Blocks | Where-Object { $_.type -eq 'page' -and $_.title -eq 'Attacker Addresses & Activity' }) | Should -Not -BeNullOrEmpty
        $IpTable = $Full.Blocks | Where-Object { $_.type -eq 'richtable' -and $_.columns[0].header -eq 'Address' }
        @($IpTable.rows).Count | Should -Be 1 -Because 'only attacker and suspicious addresses are listed'
        $IpTable.rows[0].why | Should -Be 'Proxy/VPN network; Outside the usage location; Never used by the user'
        Test-Report $Full 'Security Incident Report'
        Test-Report $Summary 'Security Incident Report'
    }

    It 'BEC: the C-suite summary marks recommended actions completed by containment instead of listing every result' {
        $BecData = @{
            ExtractedAt = '2026-09-01T00:00:00Z'
            Score       = @{ Value = 19; Level = 'High' }
            NewRules    = @(@{ Name = 'Hide' })
            Run         = @{ Containment = @(
                    @{ At = '2026-09-01T10:00:00Z'; Results = @(@{ Action = 'ResetPassword'; state = 'success' }, @{ Action = 'RevokeSessions'; state = 'success' }, @{ Action = 'DisableInboxRules'; state = 'error' }) }
                    @{ At = '2026-09-01T11:00:00Z'; Results = @(@{ Action = 'DisableAccount'; state = 'success' }) }
                ) }
        }
        $Rows = { param($r) @(($r.Blocks | Where-Object { $_.type -eq 'richtable' -and $_.columns[0].header -eq 'Priority' }).rows) }
        $Summary = Build-CippBecReportTree -TenantName 'Contoso' -UserData @{ userPrincipalName = 'alice@contoso.com' } -BecData $BecData -Variant summary
        $Actions = & $Rows $Summary
        ($Actions | Where-Object { $_.text -like 'Reset *' }).text | Should -Match "`nCompleted "
        ($Actions | Where-Object { $_.text -like 'Block sign-in*' }).text | Should -Match "`nCompleted "
        ($Actions | Where-Object { $_.text -like 'Disable the * suspicious inbox rule*' }).text | Should -Not -Match 'Completed' -Because 'an action with an error is not completed'
        ($Summary.Blocks | Where-Object { $_.type -eq 'blank' -and $_.title -eq 'Remediation Taken' }) | Should -BeNullOrEmpty
        $Full = Build-CippBecReportTree -TenantName 'Contoso' -UserData @{ userPrincipalName = 'alice@contoso.com' } -BecData $BecData
        (& $Rows $Full).text -match 'Completed' | Should -BeNullOrEmpty -Because 'the full report keeps the detailed table instead'
        ($Full.Blocks | Where-Object { $_.type -eq 'blank' -and $_.title -eq 'Remediation Taken' }) | Should -Not -BeNullOrEmpty
    }
}

Describe 'License report tree' {
    BeforeAll {
        $script:MidDot = [string][char]0x00B7
        $script:EmDash = [string][char]0x2014
        $script:Ellipsis = [string][char]0x2026
        # The branding preview sample is the rich fixture: every section populated, internally consistent totals.
        $RichPath = Join-Path $RepoRoot 'Config/ReportSamples/licensing.json'
        function Get-RichData { @{ TenantName = 'Contoso Ltd' } + (Get-Content $RichPath -Raw | ConvertFrom-Json -AsHashtable) }
        function Get-Block($Report, [string]$Type, [scriptblock]$Where = { $true }) { , @($Report.Blocks | Where-Object { $_.type -eq $Type } | Where-Object -FilterScript $Where) }
    }

    It 'quotes the headline figures the way the client did (Intl whole-unit money, JS rounding) and renders' {
        $r = Build-CippLicenseReportTree -Data (Get-RichData) -GeneratedOn 'September 23, 2026'
        $r.Variables.covermeta | Should -Be "96 people licensed $MidDot 11 plans $MidDot `$2,434 per month"
        $r.Variables.covermetanote | Should -Be 'Potential saving: $10,060 per year'
        $r.Variables.footerlabel | Should -Be "Contoso Ltd $EmDash Licensing"
        $Stats = (Get-Block $r 'scorecard')[0].stats
        @($Stats.value) | Should -Be @('$2,434', '$838', '$10,060', '27')
        @($Stats | ForEach-Object { $_.colour }) | Should -Be @($null, '#22543D', '#22543D', '#744210')
        $Alert = (Get-Block $r 'alertbox')[0]
        $Alert.title | Should -Be 'Licensing: Significant savings available'
        $Alert.content | Should -BeLike 'About 34% of the monthly licensing bill*'
        $Alert.colour | Should -Be '#742A2A'
        @((Get-Block $r 'richbullets' { $_.title -eq 'Where the savings come from' })[0].items.label) |
            Should -Be @('$413 a month by removing licenses nobody uses.', '$302 a month by moving people to a cheaper plan.', '$4 a month by combining separate plans into one bundle.', '$120 a month by paying yearly for stable seats.')
        Test-Report $r 'Microsoft 365 Licensing Review'
    }

    It 'rounds half a unit away from zero like Intl, not to even like .NET' {
        $r = Build-CippLicenseReportTree -Data (Get-RichData)
        $Downgrades = @((Get-Block $r 'richtable' { $_.columns[0].header -eq 'Current plan' })[0].rows)
        # 58.5 and 12.5 are the half-unit cases: banker's rounding would print $58 and $12.
        $Downgrades[1].saving | Should -Be '$59'
        $Downgrades[3].saving | Should -Be '$13'
        $Downgrades[1].unit | Should -Be '$6.50'
    }

    It 'builds each page from the right slice of the data' {
        $r = Build-CippLicenseReportTree -Data (Get-RichData)
        $Chart = (Get-Block $r 'chart')[0]
        $Chart.chartData.Count | Should -Be 7
        $Chart.chartData[6].label | Should -Be 'Other plans'
        $Chart.chartData[6].value | Should -Be 70.75
        $Spend = @((Get-Block $r 'richtable' { $_.columns[1].header -eq 'Owned' })[0].rows)
        ($Spend | Where-Object { $_.plan -eq 'Microsoft Teams Rooms Pro' }).monthly | Should -Be 'not priced'
        ($Spend | Where-Object { $_.plan -eq 'Microsoft Teams Rooms Pro' }).unit | Should -Be $EmDash
        ($Spend | Where-Object { $_.plan -eq 'Office 365 Extra File Storage' }).unit | Should -Be '$0.20'
        # The mailbox-only review tier claims no saving and stays off the client report.
        $Reclaim = @((Get-Block $r 'richtable' { $_.columns[1].header -eq 'Why it can go' })[0].rows)
        $Reclaim.Count | Should -Be 10
        $Reclaim[-1].saving | Should -Be 'not priced'
        # Only the first eight downgrade groups are spelled out; the rest are counted in a note.
        $Bullets = @((Get-Block $r 'richbullets' { -not $_.title -and $_.items[0].label -like '*->*' })[0].items)
        $Bullets.Count | Should -Be 8
        $Bullets[0].label | Should -Be 'Microsoft 365 Copilot -> no plan:'
        $Bullets[2].text | Should -BeLike '*Loses nothing that was used.'
        (Get-Block $r 'note' { $_.content -like '*more groups*' })[0].content | Should -Be "$Ellipsis and 2 more groups, listed in full on the admin page."
        $Terms = (Get-Block $r 'richtable' { $_.columns[2].header -like 'Held*' })[0]
        $Terms.columns[2].header | Should -Be 'Held 6+ mo'
        ($Terms.rows | Where-Object { $_.plan -eq 'Power BI Pro' }).yearlyNow | Should -Be 'unknown'
        ($Terms.rows | Where-Object { $_.plan -eq 'Power BI Pro' }).saving | Should -Be $EmDash
        (Get-Block $r 'infobox' { $_.title -eq 'Yearly seats that nobody holds' })[0].content |
            Should -Be 'Microsoft 365 E3: 2 yearly seats unassigned, renews in 200 days. Microsoft 365 Business Basic: 6 yearly seats unassigned, renews in 45 days. Microsoft 365 Apps for business: 1 yearly seat unassigned. Microsoft Teams Rooms Pro: 1 yearly seat unassigned, renews in 300 days. These are paid for until renewal; reduce the count before that date.'
        (Get-Block $r 'richbullets' { $_.items[0].label -eq 'Prices.' })[0].items.Count | Should -Be 7
    }

    It 'renders a tenant with no licenses: all-clear boxes, no chart, the empty-table note' {
        $r = Build-CippLicenseReportTree -Data @{
            TenantName   = 'Fabrikam'
            Summary      = @{ Currency = 'EUR'; InactiveDays = 30; TenureMonths = 12; ProtectSecurityFeatures = $false; MonthlySpend = 0; DataAvailable = $false }
            Products     = @(); Downgrades = @(); Upgrades = @(); Terms = @()
            Optimization = @{ Opportunities = @() }
        }
        $Euro = [string][char]0x20AC
        $r.Variables.covermeta | Should -Be "0 people licensed $MidDot 0 plans $MidDot ${Euro}0 per month"
        $r.Variables.covermetanote | Should -Be 'No savings identified'
        (Get-Block $r 'alertbox')[0].title | Should -Be 'Licensing: No priced spend'
        (Get-Block $r 'alertbox')[0].colour | Should -Be '#22543D'
        Get-Block $r 'chart' | Should -BeNullOrEmpty
        Get-Block $r 'richbullets' { $_.title -eq 'Where the savings come from' } | Should -BeNullOrEmpty
        (Get-Block $r 'richtable')[0].emptyText | Should -Be 'No licenses were found for this organisation.'
        Get-Block $r 'note' | Should -BeNullOrEmpty
        (Get-Block $r 'clearbox').Count | Should -Be 5
        (Get-Block $r 'infobox' { $_.title -eq 'What was not measured' })[0].content | Should -BeLike '*configured to treat them as optional*'
        Test-Report $r 'Microsoft 365 Licensing Review'
    }

    It 'renders an empty report (no Summary at all) without throwing' {
        $r = Build-CippLicenseReportTree -Data @{ TenantName = 'Contoso' }
        $r.Variables.covermeta | Should -Be "0 people licensed $MidDot 0 plans $MidDot `$0 per month"
        Test-Report $r 'Microsoft 365 Licensing Review'
    }

    It 'drops switched-off pages and shows only the anonymised notice when usage is anonymised' {
        $Data = Get-RichData
        $Data.Summary.AnonymizedReports = $true
        $r = Build-CippLicenseReportTree -Data $Data -Sections @{ spend = $false; reclaim = $false; downgrades = $true; upgrades = $false; terms = $false; method = $false }
        @((Get-Block $r 'page').title) | Should -Be @('Summary', 'Cheaper plans')
        (Get-Block $r 'alertbox')[-1].title | Should -Be 'Usage reports are anonymised'
        Get-Block $r 'richtable' | Should -BeNullOrEmpty
    }

    It 'keeps long headline figures and money cells whole, never broken inside the number' {
        # CHF prints as a code, so seven-digit figures overrun a stat card and the 0.9-weight money
        # columns are narrow: the kit shrinks the figure and gives the columns the client's widths.
        $Data = Get-RichData
        $Data.Summary.Currency = 'CHF'
        $Data.Summary.MonthlySpend = 3285563
        $Data.Summary.TotalPotentialAnnual = 13580460
        $r = Build-CippLicenseReportTree -Data $Data
        $Bytes = ConvertTo-CippReportPdf -Blocks $r.Blocks -Variables $r.Variables -TenantName 'Contoso' -ReportName 'T'
        $Doc = [OfficeIMO.Pdf.PdfReadDocument]::Open($Bytes)
        $Text = ($Doc.Pages | ForEach-Object { $_.ExtractText() }) -join "`n"
        # The stat row reads as one line of whole figures (the cover meta line quotes them too, so match the row).
        $Text | Should -Match 'CHF[ \xA0]3,285,563 CHF[ \xA0]838 CHF[ \xA0]13,580,460 27'
        # The consolidation table's Now and Bundle cells.
        foreach ($Figure in '14.25', '12.50') { $Text | Should -Match "CHF[ \xA0]$([regex]::Escape($Figure))" }
    }

    It 'prints an unmapped currency as its code and falls back to USD for an unusable one' {
        $r = Build-CippLicenseReportTree -Data @{ TenantName = 'C'; Summary = @{ Currency = 'chf'; MonthlySpend = 1234.5 } }
        (Get-Block $r 'scorecard')[0].stats[0].value | Should -Be 'CHF 1,235'
        $r = Build-CippLicenseReportTree -Data @{ TenantName = 'C'; Summary = @{ Currency = 'dollars'; MonthlySpend = 5 } }
        (Get-Block $r 'scorecard')[0].stats[0].value | Should -Be '$5'
    }
}
