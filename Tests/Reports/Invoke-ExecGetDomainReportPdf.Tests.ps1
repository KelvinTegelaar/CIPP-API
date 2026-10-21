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
    foreach ($Name in 'ConvertTo-CippReportPdf.ps1', 'Invoke-ExecGetDomainReportPdf.ps1') {
        . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Name | Select-Object -First 1 -ExpandProperty FullName)
    }
    function Get-CIPPTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Get-Tenants { param($TenantFilter) }
    function Get-CippReportTenantName { 'Contoso Ltd' }
    function Get-CIPPBrandingSettings { @{ colour = '#F77F00' } }
    function Get-CIPPBrandingPreset { @() }
    function Get-CIPPTextReplacement { param($Text) $Text }
    function Write-LogMessage {}
    function Get-CippException { param($Exception) @{ NormalizedError = "$($Exception)" } }
    function Get-CippErrorStatusCode { param($ErrorRecord) 500 }

    # The shape the analyser stores: the result JSON plus the per-check messages.
    function New-Result([string]$Domain, [int]$Score, [hashtable]$Overrides = @{}) {
        $Result = [ordered]@{
            Domain = $Domain; LastRefresh = '2026-10-20T03:00:00.000Z'; ScorePercentage = $Score; ScoreExplanation = ''
            NSRecords = @('ns1.contoso.com.'); MailProvider = 'Microsoft 365'; ActualMXRecords = @(@{ Priority = 0; Hostname = 'mx.contoso.com.' })
            ActualSPFRecord = 'v=spf1 -all'; SPFPassAll = $true; MXPassTest = $true
            DMARCPresent = $true; DMARCFullPolicy = 'v=DMARC1; p=reject'; DMARCActionPolicy = 'Reject'; DMARCReportingActive = $true; DMARCPercentagePass = $true
            DNSSECPresent = $false; DKIMEnabled = $true; DKIMRecords = @(@{ Selector = 'selector1'; Record = 'v=DKIM1' }); MTASTS = 'Not configured'
            EnterpriseEnrollment = 'Correct'; EnterpriseRegistration = 'No CNAME'
        }
        foreach ($k in $Overrides.Keys) { $Result[$k] = $Overrides[$k] }
        [pscustomobject]$Result
    }
    $script:Domains = @(
        @{ Domain = 'contoso.com'; Result = (New-Result 'contoso.com' 88); Checks = [pscustomobject]@{ DNSSEC = [pscustomobject]@{ Fails = @('DNSSEC is not set up for this domain.') } } }
        @{ Domain = 'fabrikam.com'; Result = (New-Result 'fabrikam.com' 50 @{ DMARCActionPolicy = 'None'; DKIMEnabled = $false }); Checks = [pscustomobject]@{ DMARC = [pscustomobject]@{ Fails = @('The domain policy is set to none.') } } }
        @{ Domain = 'tailspin.com'; Result = (New-Result 'tailspin.com' 55 @{ DMARCActionPolicy = 'None' }) }
        @{ Domain = 'contoso.onmicrosoft.com'; Result = (New-Result 'contoso.onmicrosoft.com' 43 @{ DMARCPresent = $false; MTASTS = 'Not applicable' }) }
        @{ Domain = 'contoso.net' }
    )
}

Describe 'Invoke-ExecGetDomainReportPdf' {
    BeforeEach {
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'g1'; defaultDomainName = 'contoso.onmicrosoft.com' } }
        Mock Get-CIPPAzDataTableEntity {
            foreach ($d in $script:Domains) {
                [pscustomobject]@{ RowKey = $d.Domain; TenantGUID = 'g1'; DkimSelectors = '["selector1"]'
                    DomainAnalyser = $(if ($d.Result) { ConvertTo-Json $d.Result -Depth 5 -Compress } else { '' })
                    DomainAnalyserChecks = $(if ($d.Checks) { ConvertTo-Json $d.Checks -Depth 5 -Compress })
                }
            }
        }
    }

    It 'requires a single tenant' {
        (Invoke-ExecGetDomainReportPdf -Request @{ Query = @{} } -TriggerMetadata @{}).StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        (Invoke-ExecGetDomainReportPdf -Request @{ Query = @{ tenantFilter = 'AllTenants' } } -TriggerMetadata @{}).StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'reads every analyser row of the tenant and renders one PDF named after it' {
        $Response = Invoke-ExecGetDomainReportPdf -Request @{ Query = @{ tenantFilter = 'contoso.onmicrosoft.com' }; Headers = @{} } -TriggerMetadata @{}
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.ContentType | Should -Be 'application/pdf'
        $Response.Headers.'Content-Disposition' | Should -Be 'inline; filename="Domain_Security_Assessment_contoso_onmicrosoft_com.pdf"'
        [System.Text.Encoding]::ASCII.GetString($Response.Body[0..4]) | Should -Be '%PDF-'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Filter -eq "PartitionKey eq 'TenantDomains' and TenantGUID eq 'g1'" }
    }

    It 'returns 404 when none of the tenant''s domains has been analysed' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = 'contoso.com'; TenantGUID = 'g1'; DomainAnalyser = '' } }
        (Invoke-ExecGetDomainReportPdf -Request @{ Query = @{ tenantFilter = 'contoso.onmicrosoft.com' } } -TriggerMetadata @{}).StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
    }
}

Describe 'Build-CippDomainReportTree' {
    BeforeAll {
        $script:Tree = Build-CippDomainReportTree -Data @{ TenantName = 'Contoso Ltd'; Domains = $Domains; IncludeDetails = $true }
        $script:Matrix = ($Tree.Blocks | Where-Object { $_.title -eq 'Domains at a Glance' }).rows
    }

    It 'lists every domain worst first, with not-yet-analysed domains last and Microsoft-managed checks as N/A' {
        @($Matrix.domain) | Should -Be @('contoso.onmicrosoft.com', 'fabrikam.com', 'tailspin.com', 'contoso.com', 'contoso.net')
        $Moera = $Matrix | Where-Object { $_.domain -eq 'contoso.onmicrosoft.com' }
        $Moera.cDNSSEC | Should -Be 'N/A'
        $Moera.cMTASTS | Should -Be 'N/A'
        ($Matrix | Where-Object { $_.domain -eq 'contoso.net' }).score | Should -Be 'Pending'
        ($Matrix | Where-Object { $_.domain -eq 'fabrikam.com' }).cDKIM | Should -Be 'Fail'
        ($Matrix | Where-Object { $_.domain -eq 'contoso.com' }).cDNSSEC | Should -Be 'Advised'
    }

    It 'groups priority actions by check, core checks first' {
        $Actions = ($Tree.Blocks | Where-Object { $_.title -eq 'Priority Actions' }).items
        @($Actions.label) | Should -Be @('DMARC on 3 domains:', 'DKIM on 1 domain:', 'DNSSEC on 3 domains:', 'MTA-STS on 3 domains:')
    }

    It 'gives domains that share a fix one recommendation and keeps their own findings' {
        $Advice = ($Tree.Blocks | Where-Object { $_.title -eq 'What we recommend for DMARC' }).content
        $Advice | Should -Match '\*\*fabrikam\.com, tailspin\.com:\*\* Move the policy from monitoring to enforcement\.'
        $Advice | Should -Match '\*\*contoso\.onmicrosoft\.com:\*\* Publish a DMARC policy and work towards enforcement\.'
        $Found = ($Tree.Blocks | Where-Object { $_.type -eq 'richtable' -and $_.columns.header -contains 'What we found' } | Select-Object -First 1).rows
        ($Found | Where-Object { $_.domain -eq 'fabrikam.com' }).found | Should -Be 'The policy is monitor-only (p=none). The domain policy is set to none.'
        ($Found | Where-Object { $_.domain -eq 'tailspin.com' }).found | Should -Be 'The policy is monitor-only (p=none).'
        ($Found | Where-Object { $_.domain -eq 'contoso.onmicrosoft.com' }).found | Should -Match 'next Domain Analyser run'
    }

    It 'explains a DMARC grade that DNSHealth raised no message for' {
        $NoRua = @(@{ Domain = 'contoso.com'; Result = (New-Result 'contoso.com' 75 @{ DMARCReportingActive = $false }); Checks = [pscustomobject]@{ DMARC = [pscustomobject]@{ Passes = @('The domain policy is set to reject.') } } })
        $Tree4 = Build-CippDomainReportTree -Data @{ TenantName = 'Contoso Ltd'; Domains = $NoRua }
        $Row = ($Tree4.Blocks | Where-Object { $_.type -eq 'richtable' -and $_.columns.header -contains 'What we found' } | Select-Object -First 1).rows
        $Row.label | Should -Be 'Needs attention'
        $Row.found | Should -Be 'No aggregate report address (rua=) is set.'
    }

    It 'keeps every recommendation to a short outcome without setup steps when details are off' {
        $Brief = Build-CippDomainReportTree -Data @{ TenantName = 'Contoso Ltd'; Domains = $Domains; IncludeDetails = $false }
        $Advice = @($Brief.Blocks | Where-Object { $_.title -like 'What we recommend for *' }).content -join "`n"
        $Advice | Should -Not -Match 'p=|rua=|_dmarc|_mta-sts|https://|admin center|selector|registrar|TXT'
        foreach ($Line in ($Advice -split "`n")) { ($Line -replace '^- \*\*[^*]+\*\* ').Length | Should -BeLessThan 80 }
    }
    It 'adds the desired value to each recommendation in the technical version' {
        ($Tree.Blocks | Where-Object { $_.title -eq 'What we recommend for DMARC' }).content | Should -Match '\*\*Target:\*\* v=DMARC1; p=reject; rua=mailto:<reporting address>'
        ($Tree.Blocks | Where-Object { $_.title -eq 'What we recommend for MTA-STS' }).content | Should -Match 'mode: enforce'
    }
    It 'only lists the groups a check actually has' {
        $Spf = ($Tree.Blocks | Where-Object { $_.title -eq 'SPF: no action needed' }).content
        $Spf | Should -Be '- **Passing:** contoso.onmicrosoft.com, fabrikam.com, tailspin.com, contoso.com'
        ($Tree.Blocks | Where-Object { $_.title -eq 'DNSSEC: other domains' }).content | Should -Be '- **Managed by Microsoft:** contoso.onmicrosoft.com'
    }

    It 'keeps the headline figures off the cover and drops the technical pages when asked' {
        $Tree.Variables.coversubtitle | Should -Be 'Email security and DNS health across every domain.'
        $Tree.Variables.ContainsKey('covermeta') | Should -BeFalse
        @($Tree.Blocks | Where-Object { $_.title -eq 'Technical Details' }).Count | Should -Be 1
        $Short = Build-CippDomainReportTree -Data @{ TenantName = 'Contoso Ltd'; Domains = $Domains; IncludeDetails = $false }
        @($Short.Blocks | Where-Object { $_.title -eq 'Technical Details' }).Count | Should -Be 0
    }
}
