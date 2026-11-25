BeforeDiscovery {
    $Sha256 = 'a3f5' * 16
    $Sha1 = 'b4e6' * 10
    $Md5 = 'c5d7' * 8
    $Samples = @{
        FileSha1              = $Sha1
        FileSha256            = $Sha256
        FileMd5               = $Md5
        CertificateThumbprint = $Sha1
        IpAddress             = '203.0.113.9'
        Url                   = 'https://bad.example/download'
        DomainName            = 'bad.example'
    }
}

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPDefenderIndicator { param($TenantFilter, $PageSize) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $type, $scope, $AsApp, $maxRetries) }
    function Write-LogMessage { param($headers, $API, $tenant, $tenantId, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = $Exception.Exception.Message } }
    function New-CippQueueEntry { param($Name, $Link, $Reference, $TotalTasks) }
    function Start-CIPPOrchestrator { [CmdletBinding()] param($InputObject, $InputObjectGuid, [switch]$CallerIsQueueTrigger) }
    function Update-CippQueueEntry { param($RowKey, $Status, $Name, $TotalTasks, [switch]$IncrementTotalTasks) }
    foreach ($Helper in 'Get-CippErrorStatusCode.ps1', 'Get-CippBulkStatusCode.ps1', 'Get-CIPPTenantLookup.ps1', 'Add-CIPPDefenderIndicator.ps1') {
        . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Helper -File | Select-Object -First 1 -ExpandProperty FullName)
    }

    $script:EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Security/Defender/Invoke-AddDefenderIndicator.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $script:EndpointPath -Raw)))

    $script:Sha256 = 'a3f5' * 16
    $script:Sha1 = 'b4e6' * 10
    $script:Md5 = 'c5d7' * 8
    $script:Samples = @{
        FileSha1              = $script:Sha1
        FileSha256            = $script:Sha256
        FileMd5               = $script:Md5
        CertificateThumbprint = $script:Sha1
        IpAddress             = '203.0.113.9'
        Url                   = 'https://bad.example/download'
        DomainName            = 'bad.example'
    }

    function New-Principal ([string]$UserDetails) {
        [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((@{ userDetails = $UserDetails; userRoles = @('editor') } | ConvertTo-Json -Compress)))
    }
    function New-Request ([hashtable]$Body) {
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'AddDefenderIndicator' }; Headers = @{ 'x-ms-client-principal' = (New-Principal 'tech@msp.example') }; Body = [pscustomobject]$Body }
    }
    function New-ValidBody ([hashtable]$Extra = @{}) {
        $Body = @{ tenantFilter = 'a.com'; IndicatorType = 'FileSha256'; Values = @($script:Sha256); Action = 'Block'; Title = 'Known bad installer' }
        foreach ($Key in $Extra.Keys) { $Body[$Key] = $Extra[$Key] }
        $Body
    }
    function Get-Sent { , @(foreach ($Post in $script:Posts) { $Post.Body | ConvertFrom-Json -AsHashtable }) }
}

Describe 'Invoke-AddDefenderIndicator' {
    BeforeEach {
        $script:Posts = [System.Collections.Generic.List[object]]::new()
        $script:Existing = @{}
        $script:NextId = 100
        Mock Write-LogMessage {}
        Mock Get-Tenants {
            [pscustomobject]@{ customerId = 'id-a'; defaultDomainName = 'a.com'; initialDomainName = 'a.onmicrosoft.com' }
            [pscustomobject]@{ customerId = 'id-b'; defaultDomainName = 'b.com'; initialDomainName = 'b.onmicrosoft.com' }
            [pscustomobject]@{ customerId = 'id-c'; defaultDomainName = 'c.com'; initialDomainName = 'c.onmicrosoft.com' }
        }
        Mock Get-CIPPDefenderIndicator { $script:Existing[$TenantFilter] }
        $script:Started = [System.Collections.Generic.List[object]]::new()
        Mock New-CippQueueEntry { @{ PartitionKey = 'CippQueue'; RowKey = 'queue-1'; Name = $Name; Link = $Link; TotalTasks = $TotalTasks } }
        Mock Start-CIPPOrchestrator { $script:Started.Add($InputObject) }
        Mock Update-CippQueueEntry {}
        Mock New-GraphPOSTRequest {
            $script:Posts.Add([pscustomobject]@{ Uri = $uri; Tenant = $tenantid; Body = $body; Scope = $scope; AsApp = $AsApp })
            $Sent = ($body | ConvertFrom-Json).Indicators
            [pscustomobject]@{ value = @(foreach ($Item in $Sent) { [pscustomobject]@{ id = "$(($script:NextId++))"; indicator = $Item.indicatorValue; isFailed = $false; failureReason = $null } }) }
        }
    }

    It 'declares Security.Defender.ReadWrite' {
        $Source = Get-Content -LiteralPath $script:EndpointPath -Raw
        $Source -match '\.FUNCTIONALITY\s*\r?\n\s*(\S+)' | Should -BeTrue
        $Matches[1] | Should -Be 'Entrypoint'
        $Source -match '\.ROLE\s*\r?\n\s*(\S+)' | Should -BeTrue
        $Matches[1] | Should -Be 'Security.Defender.ReadWrite'
    }

    It 'sends <Type> with <Action> to the import API with the app token' -ForEach @(
        foreach ($Type in 'FileSha1', 'FileSha256', 'FileMd5') { foreach ($Action in 'Allowed', 'Audit', 'Warn', 'Block', 'BlockAndRemediate') { @{ Type = $Type; Action = $Action; Value = $Samples[$Type] } } }
        foreach ($Action in 'Allowed', 'BlockAndRemediate') { @{ Type = 'CertificateThumbprint'; Action = $Action; Value = $Samples.CertificateThumbprint } }
        foreach ($Type in 'IpAddress', 'Url', 'DomainName') { foreach ($Action in 'Allowed', 'Audit', 'Warn', 'Block') { @{ Type = $Type; Action = $Action; Value = $Samples[$Type] } } }
    ) {
        $Body = New-ValidBody @{ IndicatorType = $Type; Action = $Action; Values = @($Value); acknowledgeAllow = $true }
        $Response = Invoke-AddDefenderIndicator -Request (New-Request $Body)
        $Response.StatusCode | Should -Be 200
        $script:Posts | Should -HaveCount 1
        $Post = $script:Posts[0]
        $Post.Uri | Should -BeExactly 'https://api.securitycenter.microsoft.com/api/indicators/import'
        $Post.Tenant | Should -BeExactly 'a.com'
        $Post.Scope | Should -Be 'https://api.securitycenter.microsoft.com/.default'
        $Post.AsApp | Should -BeTrue
        $Post.Body | Should -BeOfType [string]
        $Sent = (Get-Sent)[0].Indicators
        $Sent | Should -HaveCount 1
        $Sent[0].indicatorType | Should -BeExactly $Type
        $Sent[0].action | Should -BeExactly $Action
        $Sent[0].indicatorValue | Should -BeExactly $Value
        $Sent[0].title | Should -BeExactly 'Known bad installer'
        if ($Action -eq 'Audit') { $Sent[0].generateAlert | Should -BeTrue } else { $Sent[0].Keys | Should -Not -Contain 'generateAlert' }
        Should -Invoke Get-CIPPDefenderIndicator -Times 1 -Exactly -ParameterFilter { $TenantFilter -ceq 'a.com' }
    }

    It 'refuses <Type> with <Action> without calling Defender' -ForEach @(
        @{ Type = 'CertificateThumbprint'; Action = 'Audit'; Expect = 'Action for*' }
        @{ Type = 'CertificateThumbprint'; Action = 'Warn'; Expect = 'Action for*' }
        @{ Type = 'CertificateThumbprint'; Action = 'Block'; Expect = 'Action for*' }
        @{ Type = 'IpAddress'; Action = 'BlockAndRemediate'; Expect = 'Action for*' }
        @{ Type = 'Url'; Action = 'BlockAndRemediate'; Expect = 'Action for*' }
        @{ Type = 'DomainName'; Action = 'BlockAndRemediate'; Expect = 'Action for*' }
        @{ Type = 'FileSha256'; Action = 'Allow'; Expect = 'Action for*' }
        @{ Type = 'FileSha256'; Action = 'block'; Expect = 'Action for*' }
        @{ Type = 'FileSha256'; Action = 'AlertAndBlock'; Expect = 'Action for*' }
        @{ Type = 'FileSha256'; Action = $null; Expect = 'Action for*' }
        @{ Type = 'filesha256'; Action = 'Block'; Expect = 'IndicatorType must*' }
        @{ Type = 'EmailSender'; Action = 'Block'; Expect = 'IndicatorType must*' }
        @{ Type = $null; Action = 'Block'; Expect = 'IndicatorType must*' }
    ) {
        $Value = if ($Type -and $script:Samples.ContainsKey($Type)) { $script:Samples[$Type] } else { $script:Sha256 }
        $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ IndicatorType = $Type; Action = $Action; Values = @($Value); acknowledgeAllow = $true }))
        $Response.StatusCode | Should -Be 400
        $Response.Body.Results | Should -BeLike $Expect
        Should -Invoke Get-CIPPDefenderIndicator -Times 0 -Exactly
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'refuses the <Type> value <Value> without calling Defender' -ForEach @(
        @{ Type = 'FileSha1'; Value = 'b4e6' * 10 + 'a' }
        @{ Type = 'FileSha1'; Value = ('b4e6' * 10).Substring(1) }
        @{ Type = 'FileSha256'; Value = $Sha256.Substring(1) }
        @{ Type = 'FileSha256'; Value = $Sha256 + 'a' }
        @{ Type = 'FileSha256'; Value = 'g' + $Sha256.Substring(1) }
        @{ Type = 'FileSha256'; Value = $Sha1 }
        @{ Type = 'FileMd5'; Value = $Md5.Substring(1) }
        @{ Type = 'FileMd5'; Value = $Md5 + 'a' }
        @{ Type = 'CertificateThumbprint'; Value = $Sha256 }
        @{ Type = 'IpAddress'; Value = '10.1.2.3' }
        @{ Type = 'IpAddress'; Value = '172.16.0.1' }
        @{ Type = 'IpAddress'; Value = '192.168.1.1' }
        @{ Type = 'IpAddress'; Value = '127.0.0.1' }
        @{ Type = 'IpAddress'; Value = '169.254.1.1' }
        @{ Type = 'IpAddress'; Value = '100.64.0.1' }
        @{ Type = 'IpAddress'; Value = '0.0.0.0' }
        @{ Type = 'IpAddress'; Value = '224.0.0.1' }
        @{ Type = 'IpAddress'; Value = '255.255.255.255' }
        @{ Type = 'IpAddress'; Value = '1.2.3' }
        @{ Type = 'IpAddress'; Value = '01.2.3.4' }
        @{ Type = 'IpAddress'; Value = ('8{0}.1.1.1' -f [char]0xFF11) }
        @{ Type = 'IpAddress'; Value = '256.1.1.1' }
        @{ Type = 'IpAddress'; Value = '203.0.113.0/24' }
        @{ Type = 'IpAddress'; Value = '203.0.113.1-203.0.113.9' }
        @{ Type = 'IpAddress'; Value = '2001:db8::43' }
        @{ Type = 'IpAddress'; Value = '2001:db8:0:0:0:0:0:43' }
        @{ Type = 'IpAddress'; Value = '2001:0db8:0000:0000:0000:0000:0000:0042/128' }
        @{ Type = 'IpAddress'; Value = 'fe80:0000:0000:0000:0000:0000:0000:0001' }
        @{ Type = 'IpAddress'; Value = 'fd00:0000:0000:0000:0000:0000:0000:0001' }
        @{ Type = 'IpAddress'; Value = '0000:0000:0000:0000:0000:0000:0000:0001' }
        @{ Type = 'IpAddress'; Value = 'bad.example' }
        @{ Type = 'Url'; Value = 'bad.example/download' }
        @{ Type = 'Url'; Value = 'ftp://bad.example/file' }
        @{ Type = 'Url'; Value = 'https://' }
        @{ Type = 'Url'; Value = 'https://bad.example/a b' }
        @{ Type = 'Url'; Value = 'https://bad.example/%tenantid%' }
        @{ Type = 'Url'; Value = 'https://%tenantfilter%/x' }
        @{ Type = 'DomainName'; Value = 'https://bad.example' }
        @{ Type = 'DomainName'; Value = 'bad.example/path' }
        @{ Type = 'DomainName'; Value = '*.bad.example' }
        @{ Type = 'DomainName'; Value = 'localhost' }
        @{ Type = 'DomainName'; Value = '203.0.113.9' }
    ) {
        $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ IndicatorType = $Type; Values = @($script:Samples[$Type], $Value); Action = $(if ($Type -eq 'CertificateThumbprint') { 'BlockAndRemediate' } else { 'Block' }) }))
        $Response.StatusCode | Should -Be 400
        $Response.Body.Results | Should -BeLike "*$Value*"
        Should -Invoke Get-CIPPDefenderIndicator -Times 0 -Exactly
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'refuses a value that is not text' {
        $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ Values = @($script:Sha256, @{ value = 'x' }) }))
        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'passes a percent-encoded URL to Defender without CIPP variable expansion' {
        $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ IndicatorType = 'Url'; Values = @('https://bad.example/a%2F%3A') }))
        $Response.StatusCode | Should -Be 200
        $script:Posts[0].Body | Should -Not -Match '%'
        (Get-Sent)[0].Indicators[0].indicatorValue | Should -BeExactly 'https://bad.example/a%2f%3a'
    }

    It 'accepts the <Type> value <Value> and sends <Sent>' -ForEach @(
        @{ Type = 'IpAddress'; Value = '2001:0DB8:0000:0000:0000:0000:0000:0042'; Sent = '2001:0db8:0000:0000:0000:0000:0000:0042' }
        @{ Type = 'IpAddress'; Value = ' 198.51.100.7 '; Sent = '198.51.100.7' }
        @{ Type = 'FileSha256'; Value = $Sha256.ToUpperInvariant(); Sent = $Sha256 }
        @{ Type = 'DomainName'; Value = 'Bad.Example'; Sent = 'bad.example' }
        @{ Type = 'Url'; Value = 'https://bad.example/a%20b?q=%25tenantid%25&x=%E2%82%AC'; Sent = 'https://bad.example/a%20b?q=%25tenantid%25&x=%e2%82%ac' }
        @{ Type = 'Url'; Value = 'http://Bad.Example/Path?A="1"'; Sent = 'http://bad.example/path?a="1"' }
    ) {
        $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ IndicatorType = $Type; Values = @($Value) }))
        $Response.StatusCode | Should -Be 200
        (Get-Sent)[0].Indicators[0].indicatorValue | Should -BeExactly $Sent
    }

    It 'sends each value once, ignoring blank entries and case' {
        $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ Values = @($script:Sha256, " $($script:Sha256.ToUpperInvariant()) ", '', '  ', $null, ('d' * 64)) }))
        $Response.StatusCode | Should -Be 200
        (Get-Sent)[0].Indicators.indicatorValue | Should -Be @($script:Sha256, ('d' * 64))
        @($Response.Body.Results) | Should -HaveCount 2
    }

    It 'refuses values over 100,000 characters in total and accepts them at the limit' {
        $Long = @(foreach ($N in 1..50) { 'https://bad.example/{0:d2}/' -f $N + ('a' * 1977) })
        ($Long | Measure-Object -Property Length -Sum).Sum | Should -Be 100000
        $Accepted = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ IndicatorType = 'Url'; Values = $Long }))
        $Accepted.StatusCode | Should -Be 200
        $Refused = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ IndicatorType = 'Url'; Values = @($Long; 'https://bad.example/x') }))
        $Refused.StatusCode | Should -Be 400
        $Refused.Body.Results | Should -BeLike '*100,021 characters in total; one add takes up to 100,000*'
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly
    }

    It 'refuses <Case>' -ForEach @(
        @{ Case = 'no values'; Body = @{ Values = @() } }
        @{ Case = 'only blank values'; Body = @{ Values = @('', ' ') } }
        @{ Case = 'more than 500 values'; Body = @{ Values = @(foreach ($Index in 1..501) { '{0:x64}' -f $Index }) } }
        @{ Case = 'Allowed without the acknowledgement'; Body = @{ Action = 'Allowed' } }
        @{ Case = 'Allowed with acknowledgeAllow false'; Body = @{ Action = 'Allowed'; acknowledgeAllow = $false } }
        @{ Case = 'Allowed with acknowledgeAllow as text'; Body = @{ Action = 'Allowed'; acknowledgeAllow = 'true' } }
        @{ Case = 'a missing title'; Body = @{ Title = $null } }
        @{ Case = 'a blank title'; Body = @{ Title = '  ' } }
        @{ Case = 'a description that is not text'; Body = @{ Description = 42 } }
        @{ Case = 'an unknown severity'; Body = @{ Severity = 'Critical' } }
        @{ Case = 'an expiry in the past'; Body = @{ ExpirationTime = '2020-01-01T00:00:00Z' } }
        @{ Case = 'an expiry that is not a date'; Body = @{ ExpirationTime = 'next week' } }
        @{ Case = 'a missing tenant'; Body = @{ tenantFilter = $null } }
        @{ Case = 'an empty tenant list'; Body = @{ tenantFilter = @() } }
        @{ Case = 'a tenant group'; Body = @{ tenantFilter = 'group:7f1c' } }
        @{ Case = 'a tenant group selector'; Body = @{ tenantFilter = @([pscustomobject]@{ value = '7f1c'; type = 'Group' }) } }
        @{ Case = 'AllTenants with a named tenant'; Body = @{ tenantFilter = @('AllTenants', 'a.com') } }
        @{ Case = 'an unknown tenant'; Body = @{ tenantFilter = @('a.com', 'stranger.com') } }
        @{ Case = 'AllTenants with Allowed and no acknowledgement'; Body = @{ tenantFilter = 'AllTenants'; Action = 'Allowed' } }
        @{ Case = 'AllTenants with an invalid value'; Body = @{ tenantFilter = 'AllTenants'; Values = @('not-a-hash') } }
        @{ Case = 'two tenants with an expiry in the past'; Body = @{ tenantFilter = @('a.com', 'b.com'); ExpirationTime = '2020-01-01T00:00:00Z' } }
    ) {
        $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody $Body))
        $Response.StatusCode | Should -Be 400
        $Response.Body.Results | Should -Not -BeNullOrEmpty
        Should -Invoke Get-CIPPDefenderIndicator -Times 0 -Exactly
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        Should -Invoke New-CippQueueEntry -Times 0 -Exactly
        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
    }

    It 'adds Allowed indicators once the technician acknowledges them' {
        $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ Action = 'Allowed'; acknowledgeAllow = $true }))
        $Response.StatusCode | Should -Be 200
        (Get-Sent)[0].Indicators[0].action | Should -BeExactly 'Allowed'
    }

    It 'puts the technician and note in the description, and sends the expiry and severity' {
        $Expiry = [datetime]::UtcNow.AddDays(30).ToString('o')
        $Body = New-ValidBody @{ Description = ' Ticket "4411" at 50% '; Severity = 'High'; ExpirationTime = $Expiry; Title = ' Known bad ' }
        $null = Invoke-AddDefenderIndicator -Request (New-Request $Body)
        $Sent = (Get-Sent)[0].Indicators[0]
        $Sent.description | Should -BeExactly 'tech@msp.example via CIPP: Ticket "4411" at 50%'
        $Sent.title | Should -BeExactly 'Known bad'
        $Sent.severity | Should -BeExactly 'High'
        $script:Posts[0].Body | Should -BeLike ('*"expirationTime":"{0}"*' -f [datetime]::Parse($Expiry).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'"))
    }

    It 'names only the technician when there is no note' {
        $null = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody))
        $Sent = (Get-Sent)[0].Indicators[0]
        $Sent.description | Should -BeExactly 'tech@msp.example via CIPP'
        $Sent.Keys | Should -Not -Contain 'expirationTime'
        $Sent.Keys | Should -Not -Contain 'severity'
    }

    Context 'tenants' {
        It 'writes one tenant during the request, however it is named' {
            $Body = New-ValidBody @{ tenantFilter = @('a.com', 'id-a', 'A.onmicrosoft.com', [pscustomobject]@{ value = 'a.com'; label = 'A' }) }
            $Response = Invoke-AddDefenderIndicator -Request (New-Request $Body)
            $Response.StatusCode | Should -Be 200
            $script:Posts.Tenant | Should -Be @('a.com')
            Should -Invoke Get-CIPPDefenderIndicator -Times 1 -Exactly
            Should -Invoke New-CippQueueEntry -Times 0 -Exactly
            Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
        }

        It 'returns 500 when the tenant cannot be written' {
            Mock New-GraphPOSTRequest { throw 'Forbidden' }
            $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody))
            $Response.StatusCode | Should -Be 500
            @($Response.Body.Results.state) | Should -Be @('error')
            $Response.Body.Results[0].resultText | Should -BeLike '*Forbidden*'
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' -and $tenant -eq 'a.com' -and $tenantId -eq 'id-a' }
        }

        It 'returns 500 without writing when the tenant indicators cannot be read' {
            Mock Get-CIPPDefenderIndicator { throw 'Service unavailable' }
            $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ Values = @($script:Sha256, ('d' * 64)) }))
            $Response.StatusCode | Should -Be 500
            $script:Posts | Should -HaveCount 0
            @($Response.Body.Results) | Should -HaveCount 1
            $Response.Body.Results[0].resultText | Should -BeLike '*Nothing was added*Service unavailable*'
        }

        It 'queues <Case> with one task per tenant and answers 202' -ForEach @(
            @{ Case = 'two tenants'; Filter = @('a.com', 'B.onmicrosoft.com', 'id-a'); Expected = @('id-a', 'id-b') }
            @{ Case = 'AllTenants'; Filter = 'AllTenants'; Expected = @('id-a', 'id-b', 'id-c') }
        ) {
            $Expiry = [datetime]::UtcNow.AddHours(2)
            $Body = New-ValidBody @{ tenantFilter = $Filter; Values = @($script:Sha256, ('d' * 64)); Severity = 'High'; ExpirationTime = $Expiry.ToString('o') }
            $Response = Invoke-AddDefenderIndicator -Request (New-Request $Body)
            $Response.StatusCode | Should -Be 202
            $Response.Body.Metadata.QueueId | Should -Be 'queue-1'
            $Response.Body.Results | Should -BeExactly "Queued 2 Block FileSha256 indicators for $($Expected.Count) tenants."
            Should -Invoke New-CippQueueEntry -Times 1 -Exactly -ParameterFilter { $Name -ceq 'Add Defender indicators - Block FileSha256' -and $Link -ceq '/security/defender/indicators' -and $TotalTasks -eq $Expected.Count }
            Should -Invoke Start-CIPPOrchestrator -Times 1 -Exactly
            $script:Started | Should -HaveCount 1
            $Started = $script:Started[0]
            $Started.OrchestratorName | Should -BeExactly 'DefenderIndicatorOrchestrator'
            $Started.SkipLog | Should -BeTrue
            $Batch = @($Started.Batch)
            $Batch.TenantId | Should -Be $Expected
            foreach ($Task in $Batch) {
                $Task.FunctionName | Should -BeExactly 'ExecAddDefenderIndicator'
                $Task.QueueId | Should -Be 'queue-1'
                $Task.Values | Should -Be @($script:Sha256, ('d' * 64))
                $Template = $Task.TemplateJson | ConvertFrom-Json
                $Template.indicatorType | Should -BeExactly 'FileSha256'
                $Template.action | Should -BeExactly 'Block'
                $Template.description | Should -BeExactly 'tech@msp.example via CIPP'
                $Template.severity | Should -BeExactly 'High'
                $Task.TemplateJson | Should -BeLike ('*"expirationTime":"' + $Expiry.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'") + '"*')
            }
            Should -Invoke Get-CIPPDefenderIndicator -Times 0 -Exactly
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }

        It 'queues AllTenants even when it holds one tenant' {
            Mock Get-Tenants { [pscustomobject]@{ customerId = 'id-b'; defaultDomainName = 'b.com'; initialDomainName = 'b.onmicrosoft.com' } }
            $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ tenantFilter = 'AllTenants' }))
            $Response.StatusCode | Should -Be 202
            $Response.Body.Results | Should -BeExactly 'Queued 1 Block FileSha256 indicator for 1 tenant.'
            @($script:Started[0].Batch).TenantId | Should -Be @('id-b')
            @($script:Started[0].Batch).Tenant | Should -Be @('b.com')
            Should -Invoke New-CippQueueEntry -Times 1 -Exactly -ParameterFilter { $TotalTasks -eq 1 }
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }

        It 'queues only the tenants a restricted technician may use' {
            Mock Get-Tenants {
                [pscustomobject]@{ customerId = 'id-a'; defaultDomainName = 'a.com'; initialDomainName = 'a.onmicrosoft.com' }
                [pscustomobject]@{ customerId = 'id-c'; defaultDomainName = 'c.com'; initialDomainName = 'c.onmicrosoft.com' }
            }
            $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ tenantFilter = 'AllTenants' }))
            $Response.StatusCode | Should -Be 202
            @($script:Started[0].Batch).TenantId | Should -Be @('id-a', 'id-c')
            $Refused = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ tenantFilter = @('a.com', 'b.com') }))
            $Refused.StatusCode | Should -Be 400
            $Refused.Body.Results | Should -BeLike '*b.com*'
            Should -Invoke New-CippQueueEntry -Times 1 -Exactly
        }

        It 'refuses AllTenants when no tenant is available, before queueing' {
            Mock Get-Tenants {}
            $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ tenantFilter = 'AllTenants' }))
            $Response.StatusCode | Should -Be 400
            Should -Invoke New-CippQueueEntry -Times 0 -Exactly
            Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
        }

        It 'sends the worker only the technician name and first forwarded address of an interactive user' {
            $Request = New-Request (New-ValidBody @{ tenantFilter = 'AllTenants' })
            $Request.Headers['x-ms-client-principal-idp'] = 'azureStaticWebApps'
            $Request.Headers['x-ms-client-principal-name'] = 'tech@msp.example'
            $Request.Headers['x-forwarded-for'] = '198.51.100.20:51234, 10.0.0.4'
            $Request.Headers['cookie'] = 'session=secret'
            $null = Invoke-AddDefenderIndicator -Request $Request
            $Audit = @($script:Started[0].Batch)[0].AuditHeaders
            @($Audit.Keys | Sort-Object) | Should -Be @('x-forwarded-for', 'x-ms-client-principal')
            $Audit['x-forwarded-for'] | Should -BeExactly '198.51.100.20:51234'
            $Principal = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Audit['x-ms-client-principal'])) | ConvertFrom-Json -AsHashtable
            @($Principal.Keys) | Should -Be @('userDetails')
            $Principal.userDetails | Should -BeExactly 'tech@msp.example'
        }

        It 'sends the worker the identity provider and app id of an API client' {
            $Request = New-Request (New-ValidBody @{ tenantFilter = 'AllTenants' })
            $Request.Headers['x-ms-client-principal-idp'] = 'aad'
            $Request.Headers['x-ms-client-principal-name'] = '6b1f9a52-0000-4000-8000-00000000c1a0'
            $null = Invoke-AddDefenderIndicator -Request $Request
            $Audit = @($script:Started[0].Batch)[0].AuditHeaders
            @($Audit.Keys | Sort-Object) | Should -Be @('x-ms-client-principal-idp', 'x-ms-client-principal-name')
            $Audit['x-ms-client-principal-idp'] | Should -BeExactly 'aad'
            $Audit['x-ms-client-principal-name'] | Should -BeExactly '6b1f9a52-0000-4000-8000-00000000c1a0'
        }

        It 'returns 500 and starts nothing when the queue cannot be created' {
            Mock New-CippQueueEntry { throw 'Table unavailable' }
            $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ tenantFilter = 'AllTenants' }))
            $Response.StatusCode | Should -Be 500
            $Response.Body.Results | Should -BeLike 'Nothing was added*Table unavailable*'
            Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }

        It 'returns 500 and marks the queue failed when the orchestrator does not start' {
            Mock Start-CIPPOrchestrator { throw 'Failed to queue orchestration' }
            $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ tenantFilter = @('a.com', 'b.com') }))
            $Response.StatusCode | Should -Be 500
            $Response.Body.Results | Should -BeLike '*queue-1*Failed to queue orchestration*Check the queue and the logbook*'
            $Response.Body.Metadata | Should -BeNullOrEmpty
            Should -Invoke Update-CippQueueEntry -Times 1 -Exactly -ParameterFilter { $RowKey -eq 'queue-1' -and $Status -eq 'Failed' }
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }
    }

    Context 'existing indicators' {
        It 'skips a value that exists with another action, and adds the rest' {
            $script:Existing['a.com'] = @(@{ id = '7'; indicatorValue = $script:Sha256.ToUpperInvariant(); indicatorType = 'FileSha256'; action = 'Allowed'; rbacGroupNames = @() })
            $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ Values = @($script:Sha256, ('d' * 64)) }))
            $Response.StatusCode | Should -Be 207
            (Get-Sent)[0].Indicators.indicatorValue | Should -Be @(('d' * 64))
            $Skipped = @($Response.Body.Results.Where({ $_.value -eq $script:Sha256 }))
            $Skipped[0].state | Should -Be 'warning'
            $Skipped[0].resultText | Should -BeLike '*already exists there as Allowed*Remove it*'
        }

        It 'skips a value that exists with both the requested and another action' {
            $script:Existing['a.com'] = @(
                @{ id = '7'; indicatorValue = 'bad.example'; indicatorType = 'DomainName'; action = 'Block' }
                @{ id = '8'; indicatorValue = 'bad.example'; indicatorType = 'DomainName'; action = 'Warn' }
            )
            $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ IndicatorType = 'DomainName'; Values = @('bad.example', 'worse.example') }))
            $Response.StatusCode | Should -Be 207
            (Get-Sent)[0].Indicators.indicatorValue | Should -Be @('worse.example')
            $Response.Body.Results.Where({ $_.value -eq 'bad.example' })[0].resultText | Should -BeLike '*as Warn*'
        }

        It 'updates a value that exists with the same action' {
            $script:Existing['a.com'] = @(@{ id = '7'; indicatorValue = $script:Sha256; indicatorType = 'FileSha256'; action = 'Block'; rbacGroupNames = @() })
            $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody))
            $Response.StatusCode | Should -Be 200
            (Get-Sent)[0].Indicators.indicatorValue | Should -Be @($script:Sha256)
            $Response.Body.Results[0].resultText | Should -BeLike 'Updated Block indicator*'
        }

        It 'leaves a same action indicator with <Field> unchanged' -ForEach @(
            @{ Field = 'rbacGroupNames'; Groups = @('Servers') }
            @{ Field = 'rbacGroupIds'; Groups = @(7) }
        ) {
            $script:Existing['a.com'] = @(@{ id = '7'; indicatorValue = $script:Sha256; indicatorType = 'FileSha256'; action = 'Block'; $Field = $Groups })
            $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody))
            $Response.StatusCode | Should -Be 400
            $script:Posts | Should -HaveCount 0
            $Response.Body.Results[0].resultText | Should -BeLike '*specific device groups*'
        }

        It 'ignores the same value under another indicator type' {
            $script:Existing['a.com'] = @(@{ id = '7'; indicatorValue = $script:Sha1; indicatorType = 'CertificateThumbprint'; action = 'Allowed' })
            $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ IndicatorType = 'FileSha1'; Values = @($script:Sha1) }))
            $Response.StatusCode | Should -Be 200
            $script:Posts | Should -HaveCount 1
        }

        It 'compares URLs without regard to case, as Defender stores them in lowercase' {
            $script:Existing['a.com'] = @(@{ id = '7'; indicatorValue = 'https://bad.example/download?id=1'; indicatorType = 'Url'; action = 'Allowed' })
            $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ IndicatorType = 'Url'; Values = @('https://bad.example/Download?id=1', 'https://bad.example/other') }))
            $Response.StatusCode | Should -Be 207
            (Get-Sent)[0].Indicators.indicatorValue | Should -Be @('https://bad.example/other')
        }

        It 'returns 400 without writing when every value conflicts' {
            $script:Existing['a.com'] = @(
                @{ id = '7'; indicatorValue = $script:Sha256; indicatorType = 'FileSha256'; action = 'Allowed' }
                @{ id = '8'; indicatorValue = ('d' * 64); indicatorType = 'FileSha256'; action = 'Block'; rbacGroupNames = @('Servers') }
            )
            $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ Values = @($script:Sha256, ('d' * 64)) }))
            $Response.StatusCode | Should -Be 400
            $script:Posts | Should -HaveCount 0
            @($Response.Body.Results.state) | Should -Be @('warning', 'warning')
        }
    }

    Context 'Defender reply' {
        It 'maps a value Defender refuses to an error with its reason' {
            Mock New-GraphPOSTRequest {
                [pscustomobject]@{ value = @(
                        [pscustomobject]@{ id = '1'; indicator = $script:Sha256; isFailed = $false; failureReason = $null }
                        [pscustomobject]@{ id = $null; indicator = ('d' * 64); isFailed = $true; failureReason = 'Indicator value is not valid' }
                    ) }
            }
            $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ Values = @($script:Sha256, ('d' * 64)) }))
            $Response.StatusCode | Should -Be 207
            $Results = @($Response.Body.Results)
            $Results[0].state | Should -Be 'success'
            $Results[0].id | Should -Be '1'
            $Results[1].state | Should -Be 'error'
            $Results[1].resultText | Should -BeLike '*Indicator value is not valid*'
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*ids 1*' -and $message -notlike "*$($script:Sha256)*" }
        }

        It 'reports a value Defender does not confirm, or confirms twice, as an error' {
            Mock New-GraphPOSTRequest {
                [pscustomobject]@{ value = @(
                        [pscustomobject]@{ id = '1'; indicator = ('d' * 64); isFailed = $false }
                        [pscustomobject]@{ id = '2'; indicator = ('d' * 64); isFailed = $false }
                    ) }
            }
            $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ Values = @($script:Sha256, ('d' * 64)) }))
            $Response.StatusCode | Should -Be 500
            @($Response.Body.Results.Where({ $_.resultText -like 'Defender did not confirm*' })) | Should -HaveCount 2
        }

        It 'reports a success reply without an indicator id as unconfirmed' {
            Mock New-GraphPOSTRequest {
                [pscustomobject]@{ value = @([pscustomobject]@{ indicator = $script:Sha256; isFailed = $false }) }
            }
            $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody))
            $Response.StatusCode | Should -Be 500
            $Response.Body.Results[0].state | Should -Be 'error'
            $Response.Body.Results[0].resultText | Should -BeLike 'Defender did not confirm*'
        }

        It 'returns 500 when Defender refuses every value' {
            Mock New-GraphPOSTRequest { [pscustomobject]@{ value = @([pscustomobject]@{ indicator = $script:Sha256; isFailed = $true; failureReason = 'Invalid' }) } }
            (Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody))).StatusCode | Should -Be 500
        }
    }
}

Describe 'Invoke-AddDefenderIndicator on the Azure Functions starter' {
    BeforeAll {
        $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
        foreach ($Helper in 'Start-CIPPOrchestrator.ps1', 'Add-CippQueueMessage.ps1') {
            . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Helper -File | Select-Object -First 1 -ExpandProperty FullName)
        }
        function Get-CippTable { param($TableName) @{ TableName = $TableName } }
        function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
        function Start-NewOrchestration { param($FunctionName, $InputObject) }
        function Push-OutputBinding { param($Name, $Value) }
        $script:SavedCippNg = $env:CIPPNG
        $script:SavedDisabled = $env:AzureWebJobs_CIPPOrchestrator_Disabled
        $env:CIPPNG = $null
    }
    AfterAll {
        $env:CIPPNG = $script:SavedCippNg
        $env:AzureWebJobs_CIPPOrchestrator_Disabled = $script:SavedDisabled
    }
    BeforeEach {
        $script:Rows = [System.Collections.Generic.List[object]]::new()
        Mock Write-LogMessage {}
        Mock Get-Tenants {
            [pscustomobject]@{ customerId = 'id-a'; defaultDomainName = 'a.com'; initialDomainName = 'a.onmicrosoft.com' }
            [pscustomobject]@{ customerId = 'id-b'; defaultDomainName = 'b.com'; initialDomainName = 'b.onmicrosoft.com' }
        }
        Mock Get-CIPPDefenderIndicator {}
        Mock New-GraphPOSTRequest {}
        Mock New-CippQueueEntry { @{ PartitionKey = 'CippQueue'; RowKey = 'queue-1'; TotalTasks = $TotalTasks } }
        Mock Update-CippQueueEntry {}
        Mock Add-CIPPAzDataTableEntity { $script:Rows.Add([pscustomobject]@{ Table = $TableName; Entity = $Entity }) }
        Mock Push-OutputBinding {}
        Mock Start-NewOrchestration { 'instance-1' }
    }

    It 'stores one batch row per tenant and keeps the batch out of the stored input, with the orchestrator trigger <Trigger>' -ForEach @(
        @{ Trigger = 'disabled'; Disabled = 'true' }
        @{ Trigger = 'enabled'; Disabled = $null }
    ) {
        $env:AzureWebJobs_CIPPOrchestrator_Disabled = $Disabled
        $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ tenantFilter = 'AllTenants' }))
        $Response.StatusCode | Should -Be 202
        $BatchRows = @($script:Rows.Where({ $_.Table -eq 'CippOrchestratorBatch' }))
        $BatchRows | Should -HaveCount 2
        @(foreach ($Row in $BatchRows) { ($Row.Entity.BatchItem | ConvertFrom-Json).TenantId }) | Should -Be @('id-a', 'id-b')
        if ($Disabled) {
            $Stored = $script:Rows.Where({ $_.Table -eq 'CippOrchestratorInput' })[0].Entity.InputObject | ConvertFrom-Json
            $Stored.PSObject.Properties.Name | Should -Not -Contain 'Batch'
            $Stored.QueueFunction.FunctionName | Should -Be 'OrchestratorBatchItems'
            Should -Invoke Push-OutputBinding -Times 1 -Exactly
        } else {
            Should -Invoke Start-NewOrchestration -Times 1 -Exactly -ParameterFilter { ($InputObject | ConvertFrom-Json).PSObject.Properties.Name -notcontains 'Batch' }
        }
    }

    It 'returns 500 and marks the queue failed when <Case>' -ForEach @(
        @{ Case = 'the queue message cannot be sent'; Disabled = 'true' }
        @{ Case = 'the orchestration cannot be started'; Disabled = $null }
    ) {
        $env:AzureWebJobs_CIPPOrchestrator_Disabled = $Disabled
        $ErrorActionPreference = 'Continue'
        Mock Push-OutputBinding { throw 'Queue unavailable' }
        Mock Start-NewOrchestration { throw 'Durable client unavailable' }
        $Response = Invoke-AddDefenderIndicator -Request (New-Request (New-ValidBody @{ tenantFilter = 'AllTenants' }))
        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -BeLike 'CIPP could not confirm that it started adding the indicators for queue queue-1*Check the queue and the logbook*'
        Should -Invoke Update-CippQueueEntry -Times 1 -Exactly -ParameterFilter { $RowKey -eq 'queue-1' -and $Status -eq 'Failed' }
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }
}
