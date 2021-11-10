function Resolve-DnsHttpsQuery {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Domain,
        
        [Parameter()]
        [string]$RecordType = 'A',

        [Parameter()]
        [bool]$FullResultRecord = $False,

        [Parameter()]
        [ValidateSet('Google', 'Cloudflare')]
        [string]$Resolver = 'Google'
    )

    switch ($Resolver) {
        'Google' {
            $BaseUri = 'https://dns.google/resolve'
            $QueryTemplate = '{0}?name={1}&type={2}'
        }
        'CloudFlare' {
            $BaseUri = 'https://cloudflare-dns.com/dns-query'
            $QueryTemplate = '{0}?name={1}&type={2}&do=true'
        }
    }

    $Headers = @{
        'accept' = 'application/dns-json'
    }

    $Uri = $QueryTemplate -f $BaseUri, $Domain, $RecordType

    try {
        $Results = Invoke-RestMethod -Uri $Uri -Headers $Headers
    }
    catch {
        Write-Verbose "$Resolver DoH Query Exception - $($_.Exception.Message)" 
    }

    # Domain does not exist
    if ($Results.Status -ne 0) {
        return $Results
    }

    if (($Results.Answer | Measure-Object | Select-Object -ExpandProperty Count) -eq 0) {
        return $null
    }
    else {
        if ($RecordType -eq 'MX') {
            $FinalClean = $Results.Answer | ForEach-Object { $_.Data.Split(' ')[1] }
            return $FinalClean
        }
        if (!$FullResultRecord) {
            return $Results.Answer
        }
        else {
            return $Results
        }
    }
}

Function Read-SpfRecord {
    <#
    .SYNOPSIS
    Reads SPF record for specified domain
    
    .DESCRIPTION
    Uses Get-GoogleDNSQuery to obtain TXT records for domain, searching for v=spf1 at the beginning of the record
    Also parses include records and obtains their SPF as well
    
    .PARAMETER Domain
    Domain to obtain SPF record for
    
    .EXAMPLE
    Read-SpfRecord -Domain example.com

    .NOTES
    Author: John Duprey
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Domain,
        [string]$Level = 'Parent',
        [string]$ExpectedInclude = ''
    )
    begin {
        $SPFResults = [PSCustomObject]@{
            Domain           = $Domain
            Record           = ''
            RecordCount      = 0
            LookupCount      = 0
            AllMechanism     = ''
            ValidationPasses = New-Object System.Collections.ArrayList
            ValidationWarns  = New-Object System.Collections.ArrayList
            ValidationFails  = New-Object System.Collections.ArrayList
            Lookups          = New-Object System.Collections.ArrayList        
        }

        # Initialize lists to hold all records
        $RecordList = New-Object System.Collections.ArrayList
        $IncludeList = New-Object System.Collections.ArrayList
        $ValidationFails = New-Object System.Collections.ArrayList
        $ValidationPasses = New-Object System.Collections.ArrayList
        $ValidationWarns = New-Object System.Collections.ArrayList
        $LookupCount = 0
        $IsRedirected = $false
    }
    process {
        # Initialize lists for domain
        $DomainIncludes = New-Object System.Collections.ArrayList
        $TypeLookups = New-Object System.Collections.ArrayList
        $IPAddresses = New-Object System.Collections.ArrayList
        $AllMechanism = ''

        if (Test-Path -Path 'Config/DnsConfig.json') {
            $Config = Get-Content 'Config/DnsConfig.json' | ConvertFrom-Json
            
            $DnsQuery = @{
                RecordType = 'TXT'
                Domain     = $Domain
                Resolver   = $Config.Resolver
            }
        }
        else {
            $DnsQuery = @{
                RecordType = 'TXT'
                Domain     = $Domain
            }
        }

        # Query DNS for SPF Record
        try {
            $Query = Resolve-DnsHttpsQuery @DnsQuery

            if ($level -ne 'Parent') {
                $LookupCount++
            }

            $Record = $Query | Select-Object -ExpandProperty data | Where-Object { $_ -match '^v=spf1' }
            $RecordCount = ($Record | Measure-Object).Count
            
            # Split records and parse
            $RecordEntries = $Record -split ' '

            $RecordEntries | ForEach-Object {
                if ($_ -match 'v=spf1') {}
            
                # Look for redirect modifier
                elseif ($_ -match 'redirect=(?<Domain>.+)') {
                    if ($Record -match 'all$') {
                        $ValidationFails.Add("FAIL: $Domain - Redirect modifier should not contain all mechanism, SPF record invalid") | Out-Null
                    }
                    else {
                        $IsRedirected = $true
                        $Domain = $Matches.Domain
                    }
                }
            
                # Don't increment for include, this will be done in a recursive call
                elseif ($_ -match 'include:(.+)') {
                    $DomainIncludes.Add($Matches[1]) | Out-Null
                    $IncludeList.Add($Matches[1]) | Out-Null
                }

                # Increment lookup count for exists mechanism
                elseif ($_ -match 'exists:(.+)') {
                    $LookupCount++
                }

                # Collect explicit IP addresses
                elseif ($_ -match 'ip[4,6]:(.+)') {
                    $IPAddresses.Add($Matches[1]) | Out-Null
                }

                # Get parent level mechanism for all
                elseif ($Level -eq 'Parent' -and $_ -match 'all') {
                    if ($Record -match "$_$") {
                        $AllMechanism = $_
                    }
                }
                # Get any type specific entry
                elseif ($_ -match '^(?<RecordType>[A-Za-z]+)(?:[:])?(?<Domain>.+)?$') {
                    $LookupCount++
                    $TypeLookups.Add($_) | Out-Null
                }
            }

            # Follow redirect modifier
            if ($IsRedirected) {
                $RedirectedLookup = Read-SpfRecord -Domain $Domain -Level 'Redirect'
                if (($RedirectedLookup | Measure-Object).Count -eq 0) {
                    $ValidationFails.Add('FAIL: Redirected lookup does not contain a SPF record, permerror')
                }
            }
            else {
                # Return object containing Domain and SPF record
                $Result = [PSCustomObject]@{
                    Domain       = $Domain
                    Record       = $Record
                    RecordCount  = $RecordCount
                    Level        = $Level
                    Includes     = $DomainIncludes
                    TypeLookups  = $TypeLookups
                    IPAddresses  = $IPAddresses
                    LookupCount  = $LookupCount
                    AllMechanism = $AllMechanism
                }
                $RecordList.Add($Result) | Out-Null
            }
        }
        catch {
            # DNS Resolver exception
        }
    }
    end {
        if ($IsRedirected) {
            $RedirectedLookup
        }
        else {
            # Loop through includes and perform recursive lookup
            $IncludeHosts = $IncludeList | Sort-Object -Unique
            if (($IncludeHosts | Measure-Object).Count -gt 0) {
                foreach ($Include in $IncludeHosts) {
                    # Verify we have not performed a lookup for this nested SPF record
                    if ($RecordList.Domain -notcontains $Include) {
                        $IncludeRecords = Read-SpfRecord -Domain $Include -Level 'Include'
                        Foreach ($IncludeRecord in $IncludeRecords) {
                            $RecordList.Add($IncludeRecord) | Out-Null
                        }
                    }
                }
            }
        
            if ($Level -eq 'Parent' -or $Level -eq 'Redirect') {
                if ($ExpectedInclude -ne '') {
                    if ($Record -notcontains $ExpectedInclude) {
                        $ExpectedIncludeSpf = Read-SpfRecord -Domain $ExpectedInclude
                        $ExpectedIPList = $ExpectedIncludeSpf.Lookups.IPAddresses
                        $ExpectedIPCount = $ExpectedIPList | Measure-Object | Select-Object -ExpandProperty Count
                        $FoundIPCount = Compare-Object $RecordList.IPAddresses $ExpectedIPList -IncludeEqual | Where-Object -Property SideIndicator -EQ '==' | Measure-Object | Select-Object -ExpandProperty Count
                        if ($ExpectedIPCount -eq $FoundIPCount) {
                            Write-Verbose 'Expected SPF IP Addresses found'
                        }
                        else {
                            $ValidationFails.Add("FAIL: Expected SPF include of '$ExpectedInclude' was not found in the SPF record")
                        }
                    }
                    else {
                        Write-Verbose 'Expected SPF include found'
                    }
                }

                $LegacySpfType = Resolve-DnsHttpsQuery -Domain $Domain -RecordType 'SPF'

                if ($null -ne $LegacySpfType) {
                    $ValidationWarns.Add('WARN: DNS Record Type SPF detected, this is legacy and should not be used. It is recommeded to delete this record.')
                }

                if ($RecordCount -eq 0) { $ValidationFails.Add('FAIL: No SPF record detected') | Out-Null }
                if ($RecordCount -gt 1) { $ValidationFails.Add("FAIL: There should only be one SPF record, $RecordCount detected") | Out-Null }
    
                $LookupCount = ($RecordList | Measure-Object -Property LookupCount -Sum).Sum
                if ($LookupCount -gt 10) { 
                    $ValidationFails.Add("FAIL: SPF record exceeded 10 lookups, found $LookupCount") | Out-Null 
                }
                elseif ($LookupCount -ge 9 -and $LookupCount -lt 10) {
                    $ValidationWarns.Add("WARN: SPF lookup count is close to the limit of 10, found $LookupCount") | Out-Null
                }

                if (($ValidationFails | Measure-Object | Select-Object -ExpandProperty Count) -eq 0) {
                    $ValidationPasses.Add('PASS: No errors detected with SPF record') | Out-Null
                }

                $SpfResults.Record = $Record
                $SpfResults.RecordCount = $RecordCount
                $SpfResults.LookupCount = $LookupCount
                $SpfResults.AllMechanism = $AllMechanism
                $SpfResults.ValidationPasses = $ValidationPasses
                $SpfResults.ValidationWarns = $ValidationWarns
                $SpfResults.ValidationFails = $ValidationFails
                $SpfResults.Lookups = $RecordList
            
                # Output SpfResults object
                $SpfResults
            }
            else {
                # Return list of psobjects 
                $RecordList
            }
        }
    }
}

function Read-DmarcPolicy {
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )
    $DmarcAnalysis = [PSCustomObject]@{
        Domain           = $Domain
        Record           = ''
        Policy           = ''
        SubdomainPolicy  = ''
        FailureReport    = ''
        Percent          = 100
        ReportingEmails  = New-Object System.Collections.ArrayList
        ForensicEmails   = New-Object System.Collections.ArrayList
        ValidationPasses = New-Object System.Collections.ArrayList
        ValidationWarns  = New-Object System.Collections.ArrayList
        ValidationFails  = New-Object System.Collections.ArrayList
    }

    $ValidationPasses = New-Object System.Collections.ArrayList
    $ValidationWarns = New-Object System.Collections.ArrayList
    $ValidationFails = New-Object System.Collections.ArrayList

    $ReportDomains = New-Object System.Collections.ArrayList

    $PolicyValues = @('none', 'quarantine', 'reject')
    $FailureReportValues = @('0', '1', 'd', 's')

    if (Test-Path -Path 'Config/DnsConfig.json') {
        $Config = Get-Content 'Config/DnsConfig.json' | ConvertFrom-Json
            
        $DnsQuery = @{
            RecordType = 'TXT'
            Domain     = "_dmarc.$Domain"
            Resolver   = $Config.Resolver
        }
    }
    else {
        $DnsQuery = @{
            RecordType = 'TXT'
            Domain     = "_dmarc.$Domain"
        }
    }
    $DmarcRecord = (Resolve-DnsHttpsQuery @DnsQuery).data
    $DmarcAnalysis.Record = $DmarcRecord
    
    # Split DMARC record into name/value pairs
    $TagList = New-Object System.Collections.ArrayList
    Foreach ($Element in ($DmarcRecord -split ';').trim()) {
        $Name, $Value = $Element -split '='
        $TagList.Add([PSCustomObject]@{
                Name  = $Name
                Value = $Value
            }) | Out-Null
    }

    $x = 0
    foreach ($Tag in $TagList) {
        switch ($Tag.Name) {
            'v' {
                # REQUIRED: Version
                if ($x -ne 0) { $ValidationFails.Add('FAIL: v=DMARC1 must be at the beginning of the record') | Out-Null }
                if ($Tag.Value -ne 'DMARC1') { $ValidationFails.Add("FAIL: Version must be DMARC1 - found $($Tag.Value)") | Out-Null }
            }
            'p' {
                # REQUIRED: Policy
                if ($PolicyValues -notcontains $Tag.Value) { $ValidationFails.Add("FAIL: Policy must be one of the following - none, quarantine,reject. Found $($Tag.Value)") | Out-Null }
                if ($Tag.Value -eq 'reject') { $ValidationPasses.Add('PASS: Policy is sufficiently strict') | Out-Null }
                if ($Tag.Value -eq 'quarantine') { $ValidationWarns.Add('WARN: Policy is only partially enforced with quarantine') | Out-Null }
                if ($Tag.Value -eq 'none') { $ValidationWarns.Add('FAIL: Policy is not being enforced') | Out-Null }
                $DmarcAnalysis.Policy = $Tag.Value
            }
            'sp' {
                # Subdomain policy
                if ($PolicyValues -notcontains $Tag.Value) { $ValidationFails.Add("FAIL: Subdomain policy must be one of the following - none, quarantine,reject. Found $($Tag.Value)") | Out-Null }
                if ($Tag.Value -eq 'reject') { $ValidationPasses.Add('PASS: Subdomain policy is sufficiently strict') | Out-Null }
                if ($Tag.Value -eq 'quarantine') { $ValidationWarns.Add('WARN: Subdomain policy is only partially enforced with quarantine') | Out-Null }
                if ($Tag.Value -eq 'none') { $ValidationWarns.Add('FAIL: Subdomain policy is not being enforced') | Out-Null }
                $DmarcAnalysis.SubdomainPolicy = $Tag.Value
            }
            'rua' {
                # Aggregate report emails
                $ReportingEmails = $Tag.Value -split ','
                $ReportEmailsSet = $false
                foreach ($MailTo in $ReportingEmails) {
                    if ($MailTo -notmatch '^mailto:') { $ValidationFails.Add("FAIL: Aggregate report email must begin with 'mailto:', multiple addresses must be separated by commas - found $($Tag.Value)") | Out-Null }
                    else {
                        $ReportEmailsSet = $true
                        if ($MailTo -match '^mailto:(?<Email>.+@(?<Domain>.+))$') {
                            if ($ReportDomains -notcontains $Matches.Domain -and $Matches.Domain -ne $Domain) {
                                $ReportDomains.Add($Matches.Domain) | Out-Null
                            }
                            $DmarcAnalysis.ReportingEmails.Add($Matches.Email) | Out-Null
                        }
                    }
                    
                }
                if ($ReportEmailsSet) {
                    $ValidationPasses.Add('PASS: Aggregate reports are being sent') | Out-Null
                }
                else {
                    $ValidationWarns.Add('WARN: Aggregate reports are not being sent') | Out-Null
                }
            }
            'ruf' {
                # Forensic reporting emails
                foreach ($MailTo in ($Tag.Value -split ',')) {
                    if ($MailTo -notmatch '^mailto:') { $ValidationFails.Add("FAIL: Forensic report email must begin with 'mailto:', multiple addresses must be separated by commas - found $($Tag.Value)") | Out-Null }
                    else {
                        if ($MailTo -match '^mailto:(?<Email>.+@(?<Domain>.+))$') {
                            if ($ReportDomains -notcontains $Matches.Domain -and $Matches.Domain -ne $Domain) {
                                $ReportDomains.Add($Matches.Domain) | Out-Null
                            }
                            $DmarcAnalysis.ForensicEmails.Add($Matches.Email) | Out-Null
                        }
                    }
                }
            }
            'fo' {
                # Failure reporting options
                if ($FailureReportValues -notcontains $Tag.Value) { $ValidationFails.Add('FAIL: Failure reporting options must be 0, 1, d or s') | Out-Null }
                if ($Tag.Value -eq '1') { $ValidationPasses.Add('PASS: Failure report option 1 generates reports on SPF or DKIM misalignment') | Out-Null }
                if ($Tag.Value -eq '0') { $ValidationWarns.Add('WARN: Failure report option 0 will only generate a report on both SPF and DKIM misalignment. It is recommended to set this value to 1') | Out-Null }
                if ($Tag.Value -eq 'd') { $ValidationWarns.Add('WARN: Failure report option d will only generate a report on failed DKIM evaluation. It is recommended to set this value to 1') | Out-Null }
                if ($Tag.Value -eq 's') { $ValidationWarns.Add('WARN: Failure report option s will only generate a report on failed SPF evaluation. It is recommended to set this value to 1') | Out-Null }
                $DmarcAnalysis.FailureReport = $Tag.Value
            } 
            'pct' {
                if ($Tag.Value -gt 100 -or $Tag.Value -lt 0) { $ValidationWarns.Add('WARN: Percentage must be between 0 and 100') | Out-Null }
                $DmarcAnalysis.Percent = $Tag.Value
            }
        }
        $x++
    }

    # Check report domains for DMARC reporting record
    foreach ($ReportDomain in $ReportDomains) {
        $ReportDomainQuery = "$Domain._report._dmarc.$ReportDomain"
        $DnsQuery['Domain'] = $ReportDomainQuery
        $ReportDmarcRecord = Resolve-DnsHttpsQuery @DnsQuery

        if ($null -eq $ReportDmarcRecord) {
            $ValidationWarns.Add("WARN: Report DMARC policy for $Domain is missing from $ReportDomain, reports will not be delivered. Expected record: $Domain._report._dmarc.$ReportDomain - Expected value: v=DMARC1;") | Out-Null
        }
        elseif ($ReportDmarcRecord.data -notmatch '^v=DMARC1') {
            $ValidationWarns.Add("WARN: Report DMARC policy for $Domain is missing from $ReportDomain, reports will not be delivered. Expected record: $Domain._report._dmarc.$ReportDomain - Expected value: v=DMARC1;") | Out-Null
        }
    }

    # Check for missing record tags
    if ($DmarcAnalysis.Policy -eq '') { $ValidationFails.Add('FAIL: Policy record is missing') | Out-Null }
    if ($DmarcAnalysis.SubdomainPolicy -eq '') { $DmarcAnalysis.SubdomainPolicy = $DmarcAnalysis.Policy }
    if ($DmarcAnalysis.FailureReport -eq '' -and $null -ne $DmarcRecord) { 
        $ValidationWarns.Add('WARN: Failure report option 0 will only generate a report on both SPF and DKIM misalignment. It is recommended to set this value to 1') | Out-Null 
        $DmarcAnalysis.FailureReport = 0 
    }
    if ($DmarcAnalysis.Percent -lt 100) {
        $ValidationWarns.Add('WARN: Not all emails will be processed by the DMARC policy') | Out-Null
    }

    # Add the validation lists
    $DmarcAnalysis.ValidationPasses = $ValidationPasses
    $DmarcAnalysis.ValidationWarns = $ValidationWarns
    $DmarcAnalysis.ValidationFails = $ValidationFails

    $DmarcAnalysis
}