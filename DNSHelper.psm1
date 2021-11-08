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
            ValidationErrors = New-Object System.Collections.ArrayList
            Lookups          = New-Object System.Collections.ArrayList        
        }

        # Initialize lists to hold all records
        $RecordList = New-Object System.Collections.ArrayList
        $IncludeList = New-Object System.Collections.ArrayList
        $ValidationErrors = New-Object System.Collections.ArrayList
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
                        $ValidationErrors.Add("$Domain - Redirect modifier should not contain all mechanism, SPF record invalid") | Out-Null
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
                    $ValidationErrors.Add('Redirected lookup does not contain a SPF record, permerror')
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
                            $ValidationErrors.Add("Expected SPF include of '$ExpectedInclude' was not found in the SPF record")
                        }
                    }
                    else {
                        Write-Verbose 'Expected SPF include found'
                    }
                }

                if ($RecordCount -eq 0) { $ValidationErrors.Add('No SPF record detected') | Out-Null }
                if ($RecordCount -gt 1) { $ValidationErrors.Add("There should only be one SPF record, $RecordCount detected") | Out-Null }
    
                $LookupCount = ($RecordList | Measure-Object -Property LookupCount -Sum).Sum
                if ($LookupCount -gt 10) { $ValidationErrors.Add("SPF record exceeded 10 lookups, found $LookupCount") | Out-Null }
    
                $SpfResults.Record = $Record
                $SpfResults.RecordCount = $RecordCount
                $SpfResults.LookupCount = $LookupCount
                $SpfResults.AllMechanism = $AllMechanism
                $SpfResults.ValidationErrors = $ValidationErrors
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
