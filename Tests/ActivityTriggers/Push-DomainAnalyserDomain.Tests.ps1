BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $BackendRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Domain Analyser/Push-DomainAnalyserDomain.ps1')

    function Get-CippTable { param($tablename) @{ Name = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Name, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Name, $Entity, [switch]$Force) }
    function Set-DnsResolver { param($Resolver) }
    function Write-LogMessage { param($API, $tenant, $message, $LogData, $sev) }
    function Get-CippException { param($Exception) }
    function New-ExoRequest { }
    function Read-NSRecord { param($Domain) }
    function Read-MXRecord { param($Domain) }
    function Read-SpfRecord { param($Domain) }
    function Read-DmarcPolicy { param($Domain) }
    function Test-DNSSEC { param($Domain) }
    function Read-DkimRecord { param($Domain, $Selectors, [switch]$FallbackToMicrosoftSelectors) }
    function Resolve-DnsHttpsQuery { param($Domain, $RecordType) }
    function Read-AutoDiscoverRecord { param($Domain) }
    function Test-MtaSts { param($Domain) }

    function New-MtaSts($Record, $Mode, [bool]$Valid) {
        [pscustomobject]@{
            StsRecord = [pscustomobject]@{ Record = $Record; IsValid = $Valid }; StsPolicy = [pscustomobject]@{ Mode = $Mode; IsValid = $Valid }
            ValidationPasses = @(); ValidationWarns = @(); ValidationFails = @(if (-not $Valid) { 'MTA-STS Record is not valid' })
        }
    }
}

Describe 'Push-DomainAnalyserDomain' {
    BeforeEach {
        $script:Saved = $null
        $script:RowKey = 'contoso.com'
        Mock Get-CIPPAzDataTableEntity {
            if ($Name -eq 'Config') { [pscustomobject]@{ Resolver = 'Google' } }
            else { [pscustomobject]@{ RowKey = $script:RowKey; PartitionKey = 'TenantDomains'; TenantId = 'contoso.onmicrosoft.com'; TenantDetails = '{"Tenant":"contoso.onmicrosoft.com","TenantGUID":"g1"}' } }
        }
        Mock Add-CIPPAzDataTableEntity { if ($Name -eq 'Domains') { $script:Saved = $Entity } }
        Mock Set-DnsResolver { }
        Mock Write-LogMessage { }
        Mock Get-CippException { }
        Mock Read-NSRecord { [pscustomobject]@{ Records = @('ns1.contoso.com.') } }
        Mock Read-MXRecord { [pscustomobject]@{ Records = @('mx'); MailProvider = [pscustomobject]@{ Name = 'Microsoft 365' }; ValidationPasses = @('MX ok'); ValidationFails = @() } }
        Mock Read-SpfRecord { [pscustomobject]@{ Record = 'v=spf1 -all'; RecordCount = 1; ValidationPasses = @('SPF ok'); ValidationWarns = @('SPF note'); ValidationFails = @() } }
        Mock Read-DmarcPolicy { [pscustomobject]@{ Record = 'v=DMARC1; p=reject'; Policy = 'reject'; SubdomainPolicy = 'reject'; Percent = 100; ReportingEmails = @('a@contoso.com'); ValidationFails = @() } }
        Mock Test-DNSSEC { [pscustomobject]@{ ValidationFails = @('DNSSEC is not set up for this domain.') } }
        Mock Read-DkimRecord { [pscustomobject]@{ Records = @([pscustomobject]@{ Selector = 'selector1'; Record = 'v=DKIM1' }); Selectors = @('selector1'); ValidationFails = @() } }
        Mock Resolve-DnsHttpsQuery { [pscustomobject]@{ Answer = @() } }
        Mock Read-AutoDiscoverRecord { [pscustomobject]@{ ValidationFails = @(); ValidationWarns = @() } }
        Mock Test-MtaSts { New-MtaSts -Record '' -Mode '' -Valid $false }
    }

    It 'stores the per-check messages beside the analyser result' {
        $Result = Push-DomainAnalyserDomain -Item @{ RowKey = 'contoso.com' }
        $Result.Score | Should -Be 140
        $Checks = $script:Saved.DomainAnalyserChecks | ConvertFrom-Json
        $Checks.SPF.Warns | Should -Be @('SPF note')
        $Checks.DNSSEC.Fails | Should -Be @('DNSSEC is not set up for this domain.')
        $Checks.MX.Passes | Should -Be @('MX ok')
        @($Checks.PSObject.Properties.Name) | Should -Be @('MX', 'SPF', 'DMARC', 'DNSSEC', 'DKIM', 'MTASTS')
        $Checks.MTASTS.Fails | Should -Be @('MTA-STS Record is not valid')
        $Result.MaximumScore | Should -Be 160
    }

    It 'scores MTA-STS <status> as <score> of 160 for a custom domain' -ForEach @(
        @{ status = 'Not configured'; record = ''; mode = ''; valid = $false; score = 140 }
        @{ status = 'Enforced'; record = 'v=STSv1; id=1'; mode = 'enforce'; valid = $true; score = 150 }
        @{ status = 'Testing'; record = 'v=STSv1; id=1'; mode = 'testing'; valid = $true; score = 145 }
        @{ status = 'Invalid'; record = 'v=STSv1; id=1'; mode = 'enforce'; valid = $false; score = 140 }
    ) {
        Mock Test-MtaSts { New-MtaSts -Record $record -Mode $mode -Valid $valid }
        $Result = Push-DomainAnalyserDomain -Item @{ RowKey = 'contoso.com' }
        $Result.MTASTS | Should -Be $status
        $Result.Score | Should -Be $score
        $Result.MaximumScore | Should -Be 160
    }

    It 'gives a fully configured custom domain a high score without DNSSEC or MTA-STS' {
        $Result = Push-DomainAnalyserDomain -Item @{ RowKey = 'contoso.com' }
        $Result.ScorePercentage | Should -Be 88
        $Result.ScoreExplanation | Should -Match 'DNSSEC Not Configured'
        $Result.ScoreExplanation | Should -Match 'MTA-STS not configured'
    }

    It 'leaves DNSSEC and MTA-STS out of the score for a Microsoft-managed onmicrosoft.com domain' {
        $script:RowKey = 'contoso.onmicrosoft.com'
        $Result = Push-DomainAnalyserDomain -Item @{ RowKey = 'contoso.onmicrosoft.com' }
        $Result.MaximumScore | Should -Be 140
        $Result.Score | Should -Be 140
        $Result.ScorePercentage | Should -Be 100
        $Result.MTASTS | Should -Be 'Not applicable'
        $Result.ScoreExplanation | Should -Not -Match 'DNSSEC|MTA-STS'
        Should -Invoke Test-MtaSts -Times 0 -Exactly
    }

    It 'records an MTA-STS lookup failure as Error' {
        Mock Test-MtaSts { throw 'timeout' }
        (Push-DomainAnalyserDomain -Item @{ RowKey = 'contoso.com' }).MTASTS | Should -Be 'Error'
    }

    It 'gives no SPF points and stores no SPF check when the SPF lookup errors' {
        Mock Read-SpfRecord { throw 'timeout' }
        $Result = Push-DomainAnalyserDomain -Item @{ RowKey = 'contoso.com' }
        $Result.Score | Should -Be 110
        $Result.SPFPassAll | Should -BeFalse
        ($script:Saved.DomainAnalyserChecks | ConvertFrom-Json).PSObject.Properties.Name | Should -Not -Contain 'SPF'
    }
}
