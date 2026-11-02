# Pester tests for the Security Baseline (What-If) report: the tree builder reproduces the client
# document's content and wording from the shipped sample (Config/ReportSamples/baseline.json, the
# same data the branding preview renders), for hashtable and PSCustomObject inputs alike, and every
# variant survives a real render; the endpoint gathers the alignment, baselines and stored templates
# and validates what it is sent.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Bin = Join-Path $RepoRoot 'Shared/CIPPSharp/bin'
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Core.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Pdf.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'CIPPSharp.dll'))

    if (-not ('HttpResponseContext' -as [type])) {
        Add-Type -TypeDefinition 'public class HttpResponseContext { public object StatusCode; public object Body; public string ContentType; public object Headers; }'
    }
    $null = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')::Add('HttpStatusCode', [System.Net.HttpStatusCode])

    $Reporting = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Directory -Filter 'Reporting' | Select-Object -First 1
    Get-ChildItem -Path $Reporting.FullName -Filter '*.ps1' | ForEach-Object { . $_.FullName }
    foreach ($Name in 'ConvertTo-CippReportPdf.ps1', 'Get-CippReportTenantName.ps1', 'Invoke-ExecGetBaselineWhatIfReportPdf.ps1') {
        . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Name | Select-Object -First 1 -ExpandProperty FullName)
    }
    function Get-CIPPBrandingSettings { @{ colour = '#F77F00' } }
    function Get-CIPPBrandingPreset { param($Id, [switch]$SkipImageData) @() }
    function Write-LogMessage { param([Parameter(ValueFromRemainingArguments = $true)]$Rest) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$($Exception)" } }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }

    $script:SampleJson = Get-Content (Join-Path $RepoRoot 'Config/ReportSamples/baseline.json') -Raw
    $script:Dash = [string][char]0x2014
    $script:Dot = [string][char]0x00B7

    function ConvertTo-ReportData($Sample, [hashtable]$Override = @{}) {
        $Data = @{ TenantName = 'Contoso' }
        foreach ($Key in 'tenant', 'stageStates', 'assignedTemplates', 'simulatedTemplates', 'catalog', 'resolvers', 'sectionConfig') { $Data[$Key] = $Sample.$Key }
        foreach ($Key in $Override.Keys) { $Data[$Key] = $Override[$Key] }
        $Data
    }
    function Build-Sample([hashtable]$Override = @{}, [switch]$AsObject) {
        $Sample = if ($AsObject) { $script:SampleJson | ConvertFrom-Json } else { $script:SampleJson | ConvertFrom-Json -AsHashtable }
        Build-CippBaselineWhatIfReportTree -Data (ConvertTo-ReportData $Sample $Override)
    }
    function Get-PageTitle($Report) { @($Report.Blocks | Where-Object { $_.type -eq 'page' } | ForEach-Object { $_.title }) }
    # The first block of a type after the block titled $Title (a section's table or bullets).
    function Get-After($Report, [string]$Title, [string]$Type) {
        $Seen = $false
        foreach ($Block in $Report.Blocks) {
            if ($Seen -and $Block.type -eq $Type) { return $Block }
            if ($Block.title -eq $Title) { $Seen = $true; if ($Block.type -eq $Type) { return $Block } }
        }
    }
    function Test-Pdf($Report) {
        $Bytes = ConvertTo-CippReportPdf -Blocks $Report.Blocks -Variables $Report.Variables -TenantName 'Contoso' -ReportName 'Security Baseline Report'
        [System.Text.Encoding]::ASCII.GetString($Bytes[0..4]) | Should -Be '%PDF-'
    }

    # A tenant where every assigned standard is verified: two settings, one final wave.
    $script:Sparse = @{
        TenantName        = 'Fabrikam'
        tenant            = @{ rows = @(
                @{ standardName = 'AuditLog'; standardLabel = 'Enable the Unified Audit Log'; status = 'Compliant'; templateId = 'tpl-min'; expectedValue = @{ UnifiedAuditLogIngestionEnabled = $true }; currentValue = @{ UnifiedAuditLogIngestionEnabled = $true } }
                @{ standardName = 'DisableAppCreation'; standardLabel = 'Disable App creation by users'; status = 'Compliant'; templateId = 'tpl-min'; expectedValue = @{ allowedToCreateApps = $false }; currentValue = @{ allowedToCreateApps = $false } }
            )
        }
        stageStates       = @(@{ templateId = 'tpl-min'; templateName = 'Minimum Baseline'; currentStage = 1; totalStages = 1; stageName = 'Default'; nextStage = $null })
        assignedTemplates = @(@{ GUID = 'tpl-min'; templateName = 'Minimum Baseline'; stages = @(@{ name = 'Default'; standards = @('AuditLog', 'DisableAppCreation'); standardsConfig = @() }) })
        catalog           = ($script:SampleJson | ConvertFrom-Json -AsHashtable).catalog
    }
}

Describe 'Build-CippBaselineWhatIfReportTree' {
    It 'counts protections in place, improvements underway and pending first checks onto the cover and stat row' {
        $r = Build-Sample
        $r.Variables.covermeta | Should -Be "4 protections in place $Dot 11 improvements underway $Dot 4 applying after their first check"
        $r.Variables.covermetanote | Should -Be 'Includes a simulation of: Zero Trust'
        $r.Variables.footerlabel | Should -Be "Contoso $Dash Security Baseline"
        $r.Variables.covertitle | Should -Be 'Baseline'
        $r.Variables.coveraccent | Should -Be 'Report'
        $r.Variables.Keys | Should -Not -Contain 'coverfooternote'
        @(($r.Blocks | Where-Object { $_.type -eq 'scorecard' }).stats.value) | Should -Be @('4', '11', '4', '2')
        ($r.Blocks | Where-Object { $_.type -eq 'blank' } | Select-Object -First 1).content | Should -Match 'why each choice was made\. It also shows everything the following baseline would add: Zero Trust\.</p>$'
    }

    It 'orders the current-state table by status then name, naming a pending policy by its label rather than its template file' {
        $Table = Get-After (Build-Sample) 'Where The Baseline Stands Today' 'richtable'
        $Table.rows.Count | Should -Be 20
        @($Table.rows.statusLabel) | Should -Be @(
            @('In place') * 4 + @('Being corrected') * 6 + @('Agreed exception') * 2 + @('First check pending') * 4 +
            @('Check failed', 'License missing', 'Not applicable', 'Conflict'))
        @($Table.rows.name)[0..3] | Should -Be @('CA00 - Block legacy authentication', 'Enable all MailTips', 'Enable the Unified Audit Log', 'Windows - Defender Antivirus')
        @($Table.rows.name) | Should -Contain 'Conditional Access Template - CA05 - Require MFA for admins'
        @($Table.rows.name) | Should -Not -Match '\.json$'
        ($Table.rows | Where-Object { $_.name -eq 'Legacy retired setting' }).description | Should -Be ''
        $Table.emptyText | Should -Be 'The baseline was just assigned - the first verification run has not completed yet.'
    }

    It 'describes CA policies from their content, resolving pending and simulated ones through the stored templates' {
        $r = Build-Sample
        $Rows = (Get-After $r 'Conditional Access Policies' 'richtable').rows
        @($Rows.policy) | Should -Be @('CA01 - Require MFA for all users', 'CA05 - Require MFA for admins', 'CA10 - Require phishing-resistant MFA for admins *')
        $Rows[0].does | Should -Be 'Enforce multi-factor authentication, only allow sign-ins from approved locations, respond automatically to risky sign-ins. Deployed fully enforced from day one.'
        $Rows[0].excludes | Should -Be "Groups: CA Exclusions, Service Accounts, Break Glass +1 more`nRoles: Directory Synchronization Accounts`nGuests / external users"
        $Rows[1].does | Should -Be 'Enforce multi-factor authentication. Deployed in report-only mode first, so we can measure the impact before anyone is blocked.'
        $Rows[1].includes | Should -Be 'Roles: Global Administrator, Security Administrator'
        $Rows[2].does | Should -Be 'Require Phishing-resistant MFA (phishing-resistant) sign-in, require signing in again every 4 hours. Deployed fully enforced from day one.'
        $Rows[2].includes | Should -Be 'Roles: Global Administrator, Security Administrator, Exchange Administrator +1 more'
        # Two deployment states are spelled out per policy, so there is no single-state line.
        ($r.Blocks.content -match 'These policies will be deployed') | Should -BeNullOrEmpty
        @($r.Blocks.content -match 'added by a simulated baseline \(Zero Trust\)').Count | Should -Be 2
        $Aligned = (Get-After $r 'Conditional Access Policies In Force' 'richtable').rows
        $Aligned[0].does | Should -Be 'Block the targeted sign-ins entirely, block legacy sign-in methods that cannot do multi-factor authentication.'
        $Aligned[0].includes | Should -Be 'All users'
        $Aligned[0].excludes | Should -Be 'BreakGlass Admin'
    }

    It 'says a single deployment state once, under the table' {
        $Sample = $script:SampleJson | ConvertFrom-Json -AsHashtable
        $r = Build-CippBaselineWhatIfReportTree -Data (ConvertTo-ReportData $Sample @{ simulatedTemplates = @(); tenant = @{ rows = @($Sample.tenant.rows | Where-Object { $_.standardName -eq 'ConditionalAccessTemplate#abc123' }) } })
        (Get-After $r 'Conditional Access Policies' 'richtable').rows[0].does | Should -Not -Match 'Deployed'
        $r.Blocks.content | Should -Contain '<p>These policies will be deployed <b>fully enforced from day one</b>.</p>'
    }

    It 'names Intune policies from the stored template, the picker label or the bundle they deploy' {
        $r = Build-Sample
        $Items = (Get-After $r 'Intune Policies' 'richbullets').items
        @($Items.label) | Should -Be @('Windows - Baseline Security', 'Windows - BitLocker', "Every policy in the 'Windows Hardening' bundle")
        @($Items.text) | Should -Be @('', "(added by the 'Zero Trust' baseline)", "(added by the 'Zero Trust' baseline)")
        (Get-After $r 'Intune Policies In Force' 'richbullets').items[0].label | Should -Be 'Windows - Defender Antivirus'
    }

    It 'shows each setting today and its target with the definition variable and option labels' {
        $r = Build-Sample
        $Rows = (Get-After $r 'Settings We Will Change' 'richtable').rows
        @($Rows.setting) | Should -Be @('Set Outbound Spam Alert e-mail', 'Define Global Meeting Policy for Teams', 'Restrict guest user access to directory objects',
            'Enable Passwordless with Location information and Number Matching', 'Disable Self Service Licensing', 'Enable Customer Lockbox',
            'Disable App creation by users', 'Set Default Sharing Link Settings *', 'Default sharing to Direct users *')
        $Rows[0].today | Should -Be "Notify on outbound spam: Off`nNotify Outbound Spam Recipients: configured`nBCC suspicious outbound mail to a mailbox: Off"
        $Rows[0].change | Should -Be "Notify on outbound spam: On`nNotify Outbound Spam Recipients: security@contoso.com`nBCC suspicious outbound mail to a mailbox: Off"
        $Teams = $Rows[1].change -split "`n"
        $Teams.Count | Should -Be 9
        $Teams[8] | Should -Be "$([char]0x2026) and 2 more values"
        $Teams | Should -Contain 'Who can bypass the lobby?: People in organization excluding guests'
        $Teams | Should -Contain 'Default value of the `Who can present?`: Only organizer'
        ($Rows[1].today -split "`n") | Should -Contain 'Meeting chat policy: On for everyone'
        $Rows[2].today | Should -Be 'Guest user access level: Same access as member users'
        $Rows[2].change | Should -Be 'Guest user access level: Restricted access (guests can only see their own profile)'
        $Rows[3].today | Should -Be "State: enabled`nFeature Settings: configured"
        $Rows[4].today | Should -Be 'Not checked yet'
        $Rows[4].change | Should -Be 'Enforced as described'
        $Rows[4].why | Should -Be 'Security best practice; medium impact change for users.'
        $Rows[5].change | Should -Be 'Customer Lockbox enabled: On'
        $Rows[6].change | Should -Be 'Allow users to create app registrations: Off'
        $Rows[6].why | Should -Be 'Recommended by CIS and CIPP and SMB1001; required for CIS M365 7.0.0 (5.1.2.2); low impact change for users.'
        $Rows[7].today | Should -Be $Dash
        $Rows[7].change | Should -Be "Default Sharing Link Type: Internal - Only people in your organization`nDefault Link Permission: 1"
        # The tenant-token SiteUrl entry is left out; the simulated sharingCapability is already a row.
        $Rows[8].change | Should -Be 'Default Sharing Link Type: Direct'
        $Enforced = (Get-After $r 'Settings Enforced Today' 'richtable').rows
        $Enforced[0].value | Should -Be 'Unified Audit Log ingestion enabled: On'
        $Enforced[0].why | Should -Be 'Recommended by CIS and CIPP; required for CIS M365 7.0.0 (3.1.1); low impact change for users.'
        ($Enforced[1].value -split "`n")[3] | Should -Be 'Number of recipients to trigger the large audience MailTip (Default is 25): 25'
    }

    It 'tells the rollout in waves with a baseline prefix, an expected date and the approval clause' {
        $Items = (Get-After (Build-Sample) 'How The Rollout Works' 'richbullets').items
        @($Items.label) | Should -Be @("Core Security Baseline $Dash Wave 1 of 3 ('Foundations'):", "Core Security Baseline $Dash Wave 2 ('Hardening'):", "Device Baseline $Dash Wave 2 of 2 ('Rollout'):")
        @($Items.text) | Should -Be @(
            'live now, covering 18 protections.'
            'adds 5 more protections - Intune Template, Intune Template, Enable Security Defaults and more. Expected around October 7, 2026, after we approve the move together.'
            'live now, covering 2 protections.'
        )
    }

    It 'dates the waves in the instance timezone' {
        # The sample's next wave is due at 12:00 UTC on October 7, already October 8 at UTC+14.
        $Saved = $env:CIPP_TIMEZONE
        try {
            $env:CIPP_TIMEZONE = 'Pacific/Kiritimati'
            $Items = (Get-After (Build-Sample) 'How The Rollout Works' 'richbullets').items
        } finally { $env:CIPP_TIMEZONE = $Saved }
        $Items[1].text | Should -BeLike '*Expected around October 8, 2026,*'
    }

    It 'lists agreed exceptions with and without a reason' {
        $Items = (Get-After (Build-Sample) 'Agreed Exceptions We Will Not Change' 'richbullets').items
        @($Items.label) | Should -Be @('Enables per user MFA for all users.', 'Enable Usernames instead of pseudo anonymised names in reports')
        @($Items.text) | Should -Be @("$Dash Customer keeps per-user MFA until their migration completes in Q2.", '')
    }

    It 'reads PSCustomObject input (the live endpoint) exactly as hashtable input (the preview sample)' {
        $FromHashtable = Build-Sample
        $FromObject = Build-Sample -AsObject
        (ConvertTo-Json -InputObject $FromObject -Depth 20 -Compress) | Should -Be (ConvertTo-Json -InputObject $FromHashtable -Depth 20 -Compress)
    }

    It 'matches keys case-sensitively like the client, for PSCustomObject and hashtable input alike' {
        # The live value names its key in another case than the baseline does, so nothing projects onto
        # the baseline's keys and the whole value is shown - under its own name, not the variable's label.
        $Sample = $script:Sparse.Clone()
        $Sample.tenant = @{ rows = @($script:Sparse.tenant.rows) + @(
                @{ standardName = 'SomeExo'; standardLabel = 'Some EXO setting'; status = 'Drift'; templateId = 'tpl-min'; expectedValue = @{ enabled = $true }; currentValue = [ordered]@{ Enabled = $false; Other = 1 } }
            )
        }
        $Sample.catalog = @($script:Sparse.catalog) + @(@{ name = 'SomeExo'; label = 'Some EXO setting'; expected = @{ enabled = '%Enabled%' }; variables = @{ Enabled = @{ label = 'Turn it on' } } })
        $Json = ConvertTo-Json -InputObject $Sample -Depth 30
        foreach ($Parsed in @(($Json | ConvertFrom-Json -AsHashtable), ($Json | ConvertFrom-Json))) {
            $Row = (Get-After (Build-CippBaselineWhatIfReportTree -Data (ConvertTo-ReportData $Parsed)) 'Settings We Will Change' 'richtable').rows |
                Where-Object setting -EQ 'Some EXO setting'
            $Row.today | Should -Be "Enabled: Off`nOther: 1"
            $Row.change | Should -Be 'Turn it on: On'
        }
    }

    It 'drops the already-in-place page and the rollout section when toggled off, keeping the exceptions' {
        $r = Build-Sample @{ sectionConfig = @{ alreadyAligned = $false; rolloutStages = $false } }
        Get-PageTitle $r | Should -Be @('Executive Summary', 'Policies We Will Deploy', 'Settings We Will Change', 'Rollout Plan')
        $r.Blocks.title | Should -Not -Contain 'How The Rollout Works'
        $r.Blocks.title | Should -Contain 'Agreed Exceptions We Will Not Change'
    }

    It 'shows a fully aligned tenant with the clear box, its settings and a single unprefixed wave' {
        $r = Build-CippBaselineWhatIfReportTree -Data $script:Sparse
        Get-PageTitle $r | Should -Be @('Executive Summary', 'What Is Already In Place', 'Rollout Plan')
        ($r.Blocks | Where-Object { $_.type -eq 'clearbox' }).title | Should -Be "$([char]0x2714)$([char]0xFE0F) Fully aligned"
        $r.Variables.covermeta | Should -Be "2 protections in place $Dot 0 improvements underway"
        $r.Variables.Keys | Should -Not -Contain 'covermetanote'
        @((Get-After $r 'Where The Baseline Stands Today' 'richtable').rows.name) | Should -Be @('Disable App creation by users', 'Enable the Unified Audit Log')
        @((Get-After $r 'Settings Enforced Today' 'richtable').rows.value) | Should -Be @('Unified Audit Log ingestion enabled: On', 'Allow users to create app registrations: Off')
        $Wave = (Get-After $r 'How The Rollout Works' 'richbullets').items
        $Wave.label | Should -Be "Wave 1 of 1 ('Default'):"
        $Wave.text | Should -Be 'live now, covering 2 protections.'
    }

    It 'keeps a freshly assigned tenant to the summary, with the empty-state text in the table' {
        $r = Build-CippBaselineWhatIfReportTree -Data @{ TenantName = 'Contoso'; catalog = $script:Sparse.catalog }
        Get-PageTitle $r | Should -Be @('Executive Summary')
        @(($r.Blocks | Where-Object { $_.type -eq 'scorecard' }).stats.value) | Should -Be @('0', '0', '0', '0')
        $r.Blocks.type | Should -Not -Contain 'clearbox'
        (Get-After $r 'Where The Baseline Stands Today' 'richtable').rows.Count | Should -Be 0
        $r.Variables.covermeta | Should -Be "0 protections in place $Dot 0 improvements underway"
    }

    It 'renders every variant to a PDF' {
        Test-Pdf (Build-Sample)
        Test-Pdf (Build-Sample @{ sectionConfig = @{ alreadyAligned = $false; rolloutStages = $false } })
        Test-Pdf (Build-CippBaselineWhatIfReportTree -Data $script:Sparse)
        Test-Pdf (Build-CippBaselineWhatIfReportTree -Data @{ TenantName = 'Contoso' })
    }
}

Describe 'Invoke-ExecGetBaselineWhatIfReportPdf' {
    BeforeAll {
        $script:Sample = $script:SampleJson | ConvertFrom-Json
        function Get-Tenants { param($TenantFilter) @{ displayName = 'Contoso' } }
        function Get-CIPPBaselineAlignment { param($TenantFilter) [pscustomobject]@{ rows = $script:Sample.tenant.rows; stageStates = $script:Sample.stageStates } }
        function Get-CIPPBaseline { @($script:Sample.assignedTemplates) + @($script:Sample.simulatedTemplates) }
        function Get-CIPPBaselineDefinition { $script:Sample.catalog }
        function Get-CippTable { @{} }
        # The stored templates as the templates table holds them: CA rows keyed by file name with the
        # template GUID in its own column, Intune rows naming the policy in 'Displayname'.
        function Get-CIPPAzDataTableEntity {
            param($Filter)
            if ($Filter -like "*'CATemplate'*") {
                foreach ($Template in $script:Sample.resolvers.caByGuid.PSObject.Properties) {
                    @{ RowKey = "$($Template.Name).CATemplate.json"; GUID = $Template.Name; JSON = (ConvertTo-Json -InputObject $Template.Value -Depth 20 -Compress) }
                }
            } elseif ($Filter -like "*'IntuneTemplate'*") {
                foreach ($Template in $script:Sample.resolvers.intuneByGuid.PSObject.Properties) {
                    @{ RowKey = $Template.Name; JSON = (ConvertTo-Json -InputObject @{ Displayname = $Template.Value.displayName } -Compress) }
                }
            }
        }
        function Invoke-Report($Body) {
            Invoke-ExecGetBaselineWhatIfReportPdf -Request @{ Body = $Body; Query = @{}; Headers = @{} } -TriggerMetadata @{ FunctionName = 'ExecGetBaselineWhatIfReportPdf' }
        }
    }

    It 'renders the tenant with a simulated baseline as a PDF' {
        $Response = Invoke-Report @{ tenantFilter = 'contoso.onmicrosoft.com'; simulatedTemplateIds = @('tpl-zero-trust') }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.ContentType | Should -Be 'application/pdf'
        $Response.Headers.'Content-Disposition' | Should -Be 'inline; filename="Baseline_Report_contoso_onmicrosoft_com.pdf"'
        [System.Text.Encoding]::ASCII.GetString($Response.Body[0..4]) | Should -Be '%PDF-'
    }

    Context 'what reaches the renderer' {
        BeforeEach {
            Mock ConvertTo-CippReportPdf { [byte[]](37, 80, 68, 70, 45) }
        }

        It 'resolves pending and simulated policies through the stored templates table' {
            (Invoke-Report @{ tenantFilter = 'contoso.onmicrosoft.com'; simulatedTemplateIds = @('tpl-zero-trust') }).StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            Should -Invoke ConvertTo-CippReportPdf -Times 1 -Exactly -ParameterFilter {
                $Text = ConvertTo-Json -InputObject @($Blocks) -Depth 20 -Compress
                $ReportName -eq 'Security Baseline Report' -and $Variables.covermetanote -eq 'Includes a simulation of: Zero Trust' -and
                $Text -match '"policy":"CA05 - Require MFA for admins"' -and $Text -match 'Roles: Global Administrator, Security Administrator' -and
                $Text -match 'CA10 - Require phishing-resistant MFA for admins \*' -and $Text -match '"label":"Windows - BitLocker"'
            }
        }

        It 'simulates a baseline named more than once only once' {
            (Invoke-Report @{ tenantFilter = 'contoso.onmicrosoft.com'; simulatedTemplateIds = @('tpl-zero-trust', 'tpl-core', 'tpl-zero-trust') }).StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            Should -Invoke ConvertTo-CippReportPdf -Times 1 -Exactly -ParameterFilter { $Variables.covermetanote -eq 'Includes a simulation of: Zero Trust' }
        }

        It 'ignores the id of a baseline that is already assigned' {
            (Invoke-Report @{ tenantFilter = 'contoso.onmicrosoft.com'; simulatedTemplateIds = @('tpl-core') }).StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            Should -Invoke ConvertTo-CippReportPdf -Times 1 -Exactly -ParameterFilter { -not $Variables.Contains('covermetanote') }
        }

        It 'passes the section toggles through' {
            (Invoke-Report @{ tenantFilter = 'contoso.onmicrosoft.com'; sectionConfig = @{ alreadyAligned = $false; rolloutStages = $true } }).StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            Should -Invoke ConvertTo-CippReportPdf -Times 1 -Exactly -ParameterFilter {
                $Blocks.title -notcontains 'What Is Already In Place' -and $Blocks.title -contains 'How The Rollout Works'
            }
        }
    }

    It 'rejects <case>' -ForEach @(
        @{ case = 'a missing tenantFilter'; body = @{}; expected = 'A tenantFilter is required' }
        @{ case = 'an unknown baseline id'; body = @{ tenantFilter = 'contoso.onmicrosoft.com'; simulatedTemplateIds = @('nope') }; expected = "Unknown baseline id 'nope'." }
        @{ case = 'a section toggle that is not a boolean'; body = @{ tenantFilter = 'contoso.onmicrosoft.com'; sectionConfig = @{ alreadyAligned = 'false' } }; expected = 'sectionConfig.alreadyAligned must be true or false.' }
    ) {
        $Response = Invoke-Report $body
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body | Should -Be $expected
    }
}
