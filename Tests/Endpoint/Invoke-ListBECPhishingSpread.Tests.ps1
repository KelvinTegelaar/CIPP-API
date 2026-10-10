[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Stubs exist only so Pester can mock them.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Stubs exist only so Pester can mock them.')]
param()

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function Get-CIPPBecMessageTrace { param($TenantFilter, $SenderAddress, $RecipientAddress, $StartDate, $EndDate, $Anchor, $PageSize, $MaxPages) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Anchor, $useSystemMailbox, $NoAuthCheck) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListBECPhishingSpread.ps1' | Select-Object -First 1
    . $FunctionPath.FullName

    function New-Request {
        param([hashtable]$Query = @{})
        [pscustomobject]@{
            Params  = [pscustomobject]@{ CIPPEndpoint = 'ListBECPhishingSpread' }
            Headers = [pscustomobject]@{ 'x-ms-client-principal' = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"userDetails":"tech@msp.com"}')) }
            Query   = [pscustomobject]$Query
            Body    = $null
        }
    }
    function New-TraceRow {
        param([string]$TraceId, [string]$Recipient, [string]$Received, [string]$Subject, [string]$Status = 'Delivered')
        [pscustomobject]@{ MessageTraceId = $TraceId; RecipientAddress = $Recipient; SenderAddress = 'ceo@contos0.com'; Subject = $Subject; Status = $Status; Received = $Received; FromIP = '203.0.113.5' }
    }
    # One sender, three recipients. alice has four distinct messages (t1 appears twice, once quarantined),
    # bob is external, carol is on the second accepted domain, and the last row has no recipient at all.
    $script:Spread = @(
        (New-TraceRow -TraceId 't1' -Recipient 'Alice@Contoso.com' -Received '2026-08-20T12:00:00Z' -Subject 'Invoice 1')
        (New-TraceRow -TraceId 't1' -Recipient 'alice@contoso.com' -Received '2026-08-20T12:00:05Z' -Subject 'Invoice 1' -Status 'Quarantined')
        (New-TraceRow -TraceId 't2' -Recipient 'alice@contoso.com' -Received '2026-08-18T09:00:00Z' -Subject 'Invoice 2')
        (New-TraceRow -TraceId 't3' -Recipient 'alice@contoso.com' -Received '2026-08-19T10:00:00Z' -Subject 'Invoice 3')
        (New-TraceRow -TraceId 't4' -Recipient 'alice@contoso.com' -Received '2026-08-19T11:00:00Z' -Subject 'Invoice 4')
        (New-TraceRow -TraceId 't1' -Recipient 'bob@gmail.com' -Received '2026-08-20T12:00:00Z' -Subject 'Invoice 1')
        (New-TraceRow -TraceId 't5' -Recipient 'carol@contoso.onmicrosoft.com' -Received '2026-08-20T13:00:00Z' -Subject 'Invoice 5')
        (New-TraceRow -TraceId 't6' -Recipient '' -Received '2026-08-20T14:00:00Z' -Subject 'No recipient')
    )
}

Describe 'Invoke-ListBECPhishingSpread' {
    BeforeEach {
        Mock Get-CIPPBecMessageTrace { [pscustomobject]@{ Rows = @(); Complete = $true } }
        Mock New-ExoRequest { @([pscustomobject]@{ DomainName = 'contoso.com' }, [pscustomobject]@{ DomainName = 'Contoso.onmicrosoft.com' }) }
    }

    It 'requires a sender and traces nothing without one' {
        $Response = Invoke-ListBECPhishingSpread -Request (New-Request @{ tenantFilter = 'contoso.com' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Match '^Failed to trace the spread from .*sender is required'
        Should -Invoke Get-CIPPBecMessageTrace -Times 0
    }

    It 'traces one 7-day window by default and walks 10-day windows, newest first, for longer ranges' {
        $script:Now = (Get-Date).ToUniversalTime()
        $Response = Invoke-ListBECPhishingSpread -Request (New-Request @{ tenantFilter = 'contoso.com'; sender = 'ceo@contos0.com' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        $Response.Body.Sender | Should -Be 'ceo@contos0.com'
        $Response.Body.Days | Should -Be 7
        $Response.Body.Complete | Should -BeTrue
        $Response.Body.TotalMessages | Should -Be 0
        Should -Invoke Get-CIPPBecMessageTrace -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'contoso.com' -and $SenderAddress -eq 'ceo@contos0.com' -and [math]::Round(($EndDate - $StartDate).TotalDays) -eq 7 }
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter { $tenantid -eq 'contoso.com' -and $cmdlet -eq 'Get-AcceptedDomain' }

        $null = Invoke-ListBECPhishingSpread -Request (New-Request @{ tenantFilter = 'contoso.com'; sender = 'ceo@contos0.com'; days = '25' }) -TriggerMetadata $null
        Should -Invoke Get-CIPPBecMessageTrace -Times 4 -Exactly -Because '25 days is three windows on top of the default run'
        Should -Invoke Get-CIPPBecMessageTrace -Times 3 -Exactly -ParameterFilter { ($EndDate - $StartDate).TotalDays -le 10 -and $StartDate -le $script:Now.AddDays(-10).AddMinutes(1) -and $StartDate -ge $script:Now.AddDays(-25).AddMinutes(-1) -and $EndDate -le $script:Now.AddMinutes(1) -and $EndDate -gt $StartDate } -Because 'the 25-day run starts its windows at -10, -20 and -25 days; the default run started at -7'
        Should -Invoke Get-CIPPBecMessageTrace -Times 1 -Exactly -ParameterFilter { [math]::Round(($EndDate - $StartDate).TotalDays) -eq 5 } -Because 'the oldest window is clipped to the range start'
    }

    It 'clamps the look-back to 1-90 days' {
        $Long = Invoke-ListBECPhishingSpread -Request (New-Request @{ tenantFilter = 'contoso.com'; sender = 'ceo@contos0.com'; days = '500' }) -TriggerMetadata $null
        $Long.StatusCode | Should -Be 200
        $Long.Body.Days | Should -Be 90
        Should -Invoke Get-CIPPBecMessageTrace -Times 9 -Exactly
        $Short = Invoke-ListBECPhishingSpread -Request (New-Request @{ tenantFilter = 'contoso.com'; sender = 'ceo@contos0.com'; days = '0' }) -TriggerMetadata $null
        $Short.Body.Days | Should -Be 1
        Should -Invoke Get-CIPPBecMessageTrace -Times 10 -Exactly
    }

    It 'reports a non-numeric look-back as a formatted error instead of crashing' {
        $Response = Invoke-ListBECPhishingSpread -Request (New-Request @{ tenantFilter = 'contoso.com'; sender = 'ceo@contos0.com'; days = 'soon' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Match '^Failed to trace the spread from ceo@contos0\.com: .+'
        Should -Invoke Get-CIPPBecMessageTrace -Times 0
    }

    It 'groups the rows per recipient: internal from the accepted domains, distinct message count, first and last delivery, statuses and up to three subjects' {
        Mock Get-CIPPBecMessageTrace { [pscustomobject]@{ Rows = $script:Spread; Complete = $true } }
        $Response = Invoke-ListBECPhishingSpread -Request (New-Request @{ tenantFilter = 'contoso.com'; sender = 'ceo@contos0.com' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        $Response.Body.TotalMessages | Should -Be 6 -Because 'six distinct trace ids were returned'
        $Response.Body.InternalCount | Should -Be 2
        $Response.Body.ExternalCount | Should -Be 1
        @($Response.Body.Recipients).Recipient | Should -Be @('alice@contoso.com', 'carol@contoso.onmicrosoft.com', 'bob@gmail.com') -Because 'internal recipients sort first, then by address; the row without a recipient is dropped and case is folded'
        $Alice = $Response.Body.Recipients[0]
        $Alice.Internal | Should -BeTrue
        $Alice.MessageCount | Should -Be 4 -Because 'the two t1 rows are one message'
        $Alice.FirstReceived | Should -Be '2026-08-18T09:00:00Z'
        $Alice.LastReceived | Should -Be '2026-08-20T12:00:05Z'
        $Alice.Statuses | Should -Be 'Delivered, Quarantined'
        $Alice.Subjects | Should -Be 'Invoice 1 | Invoice 2 | Invoice 3' -Because 'subjects are capped at three'
        $Response.Body.Recipients[1].Internal | Should -BeTrue -Because 'accepted domains match case-insensitively'
        $Response.Body.Recipients[2].Internal | Should -BeFalse
        $Response.Body.Recipients[2].MessageCount | Should -Be 1
    }

    It 'narrows the trace to subjects containing the fragment, case-insensitively' {
        Mock Get-CIPPBecMessageTrace { [pscustomobject]@{ Rows = $script:Spread; Complete = $true } }
        $Response = Invoke-ListBECPhishingSpread -Request (New-Request @{ tenantFilter = 'contoso.com'; sender = 'ceo@contos0.com'; subject = 'INVOICE 1' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        $Response.Body.TotalMessages | Should -Be 1
        @($Response.Body.Recipients).Recipient | Should -Be @('alice@contoso.com', 'bob@gmail.com')
        $Response.Body.Recipients[0].MessageCount | Should -Be 1
        $Response.Body.Recipients[0].Subjects | Should -Be 'Invoice 1'
        $Response.Body.InternalCount | Should -Be 1
        $Response.Body.ExternalCount | Should -Be 1
    }

    It 'reports Complete=false when any window hit the page cap' {
        Mock Get-CIPPBecMessageTrace { [pscustomobject]@{ Rows = @(); Complete = $false } } -ParameterFilter { $EndDate -lt (Get-Date).ToUniversalTime().AddDays(-5) }
        $Response = Invoke-ListBECPhishingSpread -Request (New-Request @{ tenantFilter = 'contoso.com'; sender = 'ceo@contos0.com'; days = '30' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        $Response.Body.Complete | Should -BeFalse -Because 'the newest window was complete but the two older ones were not'
        Should -Invoke Get-CIPPBecMessageTrace -Times 3 -Exactly
    }

    It 'marks nobody internal when the accepted domains cannot be read' {
        Mock New-ExoRequest { throw 'EXO unavailable' }
        Mock Get-CIPPBecMessageTrace { [pscustomobject]@{ Rows = $script:Spread; Complete = $true } }
        $Response = Invoke-ListBECPhishingSpread -Request (New-Request @{ tenantFilter = 'contoso.com'; sender = 'ceo@contos0.com' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200 -Because 'the accepted-domain lookup is best effort'
        $Response.Body.InternalCount | Should -Be 0
        $Response.Body.ExternalCount | Should -Be 3
        @($Response.Body.Recipients).Recipient | Should -Be @('alice@contoso.com', 'bob@gmail.com', 'carol@contoso.onmicrosoft.com')
    }
}
