function Resolve-DnsHttpsQuery {
    <#
    .SYNOPSIS
    Resolves DNS record using DoH JSON query
    
    .DESCRIPTION
    This function uses Google or Cloudflare DoH REST APIs to resolve DNS records
    
    .PARAMETER Domain
    Domain to query
    
    .PARAMETER RecordType
    Type of record - Examples: A, CNAME, MX, TXT
    
    .EXAMPLE
    PS> Resolve-DnsHttpsQuery -Domain google.com -RecordType A
    
    name        type TTL data
    ----        ---- --- ----
    google.com.    1  30 142.250.80.110
    
    #>
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Domain,
        
        [Parameter()]
        [string]$RecordType = 'A'
    )

    if (Test-Path -Path 'Config\DnsConfig.json') {
        try {
            $Config = Get-Content 'Config\DnsConfig.json' | ConvertFrom-Json 
            $Resolver = $Config.Resolver
        }
        catch { $Resolver = 'Google' }
    }
    else {
        $Resolver = 'Google'
    }

    switch ($Resolver) {
        'Google' {
            $BaseUri = 'https://dns.google/resolve'
            $QueryTemplate = '{0}?name={1}&type={2}'
        }
        'CloudFlare' {
            $BaseUri = 'https://cloudflare-dns.com/dns-query'
            $QueryTemplate = '{0}?name={1}&type={2}'
        }
    }

    $Headers = @{
        'accept' = 'application/dns-json'
    }

    $Uri = $QueryTemplate -f $BaseUri, $Domain, $RecordType

    Write-Verbose "### $Uri ###"
 
    try {
        $Results = Invoke-RestMethod -Uri $Uri -Headers $Headers -ErrorAction Stop
    }
    catch {
        Write-Verbose "$Resolver DoH Query Exception - $($_.Exception.Message)" 
        return $null
    }
    
    if ($Resolver -eq 'Cloudflare' -and $RecordType -eq 'txt' -and $Results.Answer) {
        $Results.Answer | ForEach-Object {
            $_.data = $_.data -replace '"' -replace '\s+', ' '
        }
    }
    
    #Write-Verbose ($Results | ConvertTo-Json)
    return $Results
}

function Test-DNSSEC {
    <#
    .SYNOPSIS
    Test Domain for DNSSEC validation
    
    .DESCRIPTION
    Requests dnskey record from DNS and checks response validation (AD=True)
    
    .PARAMETER Domain
    Domain to check
    
    .EXAMPLE
    PS> Test-DNSSEC -Domain example.com
    
    Domain           : example.com
    ValidationPasses : {PASS: example.com - DNSSEC enabled and validated}
    ValidationFails  : {}
    Keys             : {...}

    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )
    $DSResults = [PSCustomObject]@{
        Domain           = $Domain
        ValidationPasses = New-Object System.Collections.Generic.List[string]
        ValidationWarns  = New-Object System.Collections.Generic.List[string]
        ValidationFails  = New-Object System.Collections.Generic.List[string]
        Keys             = New-Object System.Collections.Generic.List[string]
    }
    $ValidationPasses = New-Object System.Collections.Generic.List[string]
    $ValidationFails = New-Object System.Collections.Generic.List[string]

    $DnsQuery = @{
        RecordType = 'dnskey'
        Domain     = $Domain
    }

    $Result = Resolve-DnsHttpsQuery @DnsQuery

    $RecordCount = ($Result.Answer.data | Measure-Object).Count
    if ($null -eq $Result) {
        $ValidationFails.Add('FAIL: DNSSEC validation failed, no dnskey record found') | Out-Null
    }
    else {
        if ($Result.Status -eq 2) {
            if ($Result.AD -eq $false) {
                $ValidationFails.Add("FAIL: $($Result.Comment)") | Out-Null
            }
        }
        elseif ($Result.Status -eq 3) {
            $ValidationFails.Add('FAIL: Record does not exist (NXDOMAIN)') | Out-Null
        }
        elseif ($RecordCount -gt 0) {
            if ($Result.AD -eq $false) {
                $ValidationFails.Add('FAIL: DNSSEC enabled, but response was not validated. Ensure DNSSEC has been enabled at your registrar') | Out-Null
            }
            else {
                $ValidationPasses.Add('PASS: DNSSEC enabled and validated for this domain') | Out-Null
            }
            $DSResults.Keys = $Result.answer.data
        }
        else {
            $ValidationFails.Add('FAIL: DNSSEC validation failed, no dnskey record found') | Out-Null
        }
    }

    $DSResults.ValidationPasses = $ValidationPasses
    $DSResults.ValidationFails = $ValidationFails
    $DSResults
}

function Read-NSRecord {
    <#
    .SYNOPSIS
    Reads NS records for domain
    
    .DESCRIPTION
    Queries DNS servers to get NS records and returns in PSCustomObject list
    
    .PARAMETER Domain
    Domain to query
    
    .EXAMPLE
    PS> Read-NSRecord -Domain gmail.com
    
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )
    $NSResults = [PSCustomObject]@{
        Domain           = ''
        Records          = New-Object System.Collections.Generic.List[PSCustomObject]
        ValidationPasses = New-Object System.Collections.Generic.List[string]
        ValidationWarns  = New-Object System.Collections.Generic.List[string]
        ValidationFails  = New-Object System.Collections.Generic.List[string]
        NameProvider     = ''
    }
    $ValidationPasses = New-Object System.Collections.Generic.List[string]
    $ValidationFails = New-Object System.Collections.Generic.List[string]

    $DnsQuery = @{
        RecordType = 'ns'
        Domain     = $Domain
    }
 
    $NSResults.Domain = $Domain

    try {
        $Result = Resolve-DnsHttpsQuery @DnsQuery
    }
    catch { $Result = $null }
    if ($Result.Status -ne 0 -or -not ($Result.Answer)) {
        $ValidationFails.Add("FAIL: $Domain - NS record does not exist") | Out-Null
        $NSRecords = $null
    }
    else {
        $NSRecords = $Result.Answer.data
        $ValidationPasses.Add("PASS: $Domain - NS record is present") | Out-Null
        $NSResults.Records = $NSRecords
    }
    $NSResults.ValidationPasses = $ValidationPasses
    $NSResults.ValidationFails = $ValidationFails
    $NSResults
}

function Read-MXRecord {
    <#
    .SYNOPSIS
    Reads MX records for domain
    
    .DESCRIPTION
    Queries DNS servers to get MX records and returns in PSCustomObject list with Preference and Hostname
    
    .PARAMETER Domain
    Domain to query
    
    .EXAMPLE
    PS> Read-MXRecord -Domain gmail.com
    
    Preference Hostname
    ---------- --------
       5 gmail-smtp-in.l.google.com.
      10 alt1.gmail-smtp-in.l.google.com.
      20 alt2.gmail-smtp-in.l.google.com.
      30 alt3.gmail-smtp-in.l.google.com.
      40 alt4.gmail-smtp-in.l.google.com.
    
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )
    $MXResults = [PSCustomObject]@{
        Domain           = ''
        Records          = New-Object System.Collections.Generic.List[PSCustomObject]
        ValidationPasses = New-Object System.Collections.Generic.List[string]
        ValidationWarns  = New-Object System.Collections.Generic.List[string]
        ValidationFails  = New-Object System.Collections.Generic.List[string]
        MailProvider     = ''
        ExpectedInclude  = ''
        Selectors        = ''
    }
    $ValidationPasses = New-Object System.Collections.Generic.List[string]
    $ValidationFails = New-Object System.Collections.Generic.List[string]

    $DnsQuery = @{
        RecordType = 'mx'
        Domain     = $Domain
    }
 
    $MXResults.Domain = $Domain

    try {
        $Result = Resolve-DnsHttpsQuery @DnsQuery
    }
    catch { $Result = $null }
    if ($Result.Status -ne 0 -or -not ($Result.Answer)) {
        if ($Result.Status -eq 3) {
            $ValidationFails.Add('FAIL: Record does not exist (nxdomain). If you do not want to receive mail for this domain use a Null MX record of . with a priority 0 (RFC 7505)') | Out-Null
            $MXResults.MailProvider = Get-Content 'MailProviders\Null.json' | ConvertFrom-Json
            $MXResults.Selectors = $MXRecords.MailProvider.Selectors
        }
        else {
            $ValidationFails.Add("FAIL: $Domain - MX record does not exist, if you do not want to receive mail for this domain use a Null MX record of . with a priority 0 (RFC 7505)") | Out-Null
            $MXResults.MailProvider = Get-Content 'MailProviders\Null.json' | ConvertFrom-Json
            $MXResults.Selectors = $MXRecords.MailProvider.Selectors
        }
        $MXRecords = $null
    }
    else {
        $MXRecords = $Result.Answer | ForEach-Object { 
            $Priority, $Hostname = $_.Data.Split(' ')
            try {
                [PSCustomObject]@{
                    Priority = [int]$Priority
                    Hostname = $Hostname
                }
            }
            catch {}
        }
        $ValidationPasses.Add("PASS: $Domain - MX record is present") | Out-Null
        $MXRecords = $MXRecords | Sort-Object -Property Priority

        # Attempt to identify mail provider based on MX record
        if (Test-Path 'MailProviders') {
            $ReservedVariables = @{
                'DomainNameDashNotation' = $Domain -replace '\.', '-'
            }
            if ($MXRecords.Hostname -eq '') {
                $ValidationFails.Add("FAIL: Blank MX record found for $Domain, if you do not want to receive mail for this domain use a Null MX record of . with a priority 0 (RFC 7505)") | Out-Null
                $MXResults.MailProvider = Get-Content 'MailProviders\Null.json' | ConvertFrom-Json
            }
            else {
                Get-ChildItem 'MailProviders' -Exclude '_template.json' | ForEach-Object {
                    try {
                        $Provider = Get-Content $_ | ConvertFrom-Json -ErrorAction Stop
                        $MXRecords.Hostname | ForEach-Object {
                            if ($_ -match $Provider.MxMatch) {
                                $MXResults.MailProvider = $Provider
                                if (($Provider.SpfReplace | Measure-Object | Select-Object -ExpandProperty Count) -gt 0) {
                                    $ReplaceList = New-Object System.Collections.Generic.List[string]
                                    foreach ($Var in $Provider.SpfReplace) { 
                                        if ($ReservedVariables.Keys -contains $Var) {
                                            $ReplaceList.Add($ReservedVariables.$Var) | Out-Null
                                        } 
                                        else {
                                            $ReplaceList.Add($Matches.$Var) | Out-Null
                                        }
                                    }

                                    $ExpectedInclude = $Provider.SpfInclude -f ($ReplaceList -join ',')
                                }
                                else {
                                    $ExpectedInclude = $Provider.SpfInclude
                                }

                                # Set ExpectedInclude and Selector fields based on provider details
                                $MXResults.ExpectedInclude = $ExpectedInclude
                                $MXResults.Selectors = $Provider.Selectors
                            }
                        }
                    }
                    catch {}
                }
            }
        }
        $MXResults.Records = $MXRecords
    }
    $MXResults.ValidationPasses = $ValidationPasses
    $MXResults.ValidationFails = $ValidationFails
    $MXResults
}

function Read-SpfRecord {
    <#
    .SYNOPSIS
    Reads SPF record for specified domain
    
    .DESCRIPTION
    Uses Get-GoogleDNSQuery to obtain TXT records for domain, searching for v=spf1 at the beginning of the record
    Also parses include records and obtains their SPF as well
    
    .PARAMETER Domain
    Domain to obtain SPF record for
    
    .EXAMPLE
    PS> Read-SpfRecord -Domain gmail.com

    Domain           : gmail.com
    Record           : v=spf1 redirect=_spf.google.com
    RecordCount      : 1
    LookupCount      : 4
    AllMechanism     : ~
    ValidationPasses : {PASS: Expected SPF record was included, PASS: No PermError detected in SPF record}
    ValidationWarns  : {}
    ValidationFails  : {FAIL: SPF record should end in -all to prevent spamming}
    RecordList       : {@{Domain=_spf.google.com; Record=v=spf1 include:_netblocks.google.com include:_netblocks2.google.com include:_netblocks3.google.com ~all;           RecordCount=1; LookupCount=4; AllMechanism=~; ValidationPasses=System.Collections.ArrayList; ValidationWarns=System.Collections.ArrayList; ValidationFails=System.Collections.ArrayList; RecordList=System.Collections.ArrayList; TypeLookups=System.Collections.ArrayList; IPAddresses=System.Collections.ArrayList; PermError=False}}
    TypeLookups      : {}
    IPAddresses      : {}
    PermError        : False

    .NOTES
    Author: John Duprey
    #>
    [CmdletBinding(DefaultParameterSetName = 'Lookup')]
    Param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Lookup')]
        [Parameter(ParameterSetName = 'Manual')]
        [string]$Domain,

        [Parameter(Mandatory = $true, ParameterSetName = 'Manual')]
        [string]$Record,

        [Parameter(ParameterSetName = 'Lookup')]
        [Parameter(ParameterSetName = 'Manual')]
        [string]$Level = 'Parent',

        [Parameter(ParameterSetName = 'Lookup')]
        [Parameter(ParameterSetName = 'Manual')]
        [string]$ExpectedInclude = ''
    )
    $SPFResults = [PSCustomObject]@{
        Domain           = ''
        Record           = ''
        RecordCount      = 0
        LookupCount      = 0
        AllMechanism     = ''
        ValidationPasses = New-Object System.Collections.Generic.List[string]
        ValidationWarns  = New-Object System.Collections.Generic.List[string]
        ValidationFails  = New-Object System.Collections.Generic.List[string]
        RecordList       = New-Object System.Collections.Generic.List[PSCustomObject]   
        TypeLookups      = New-Object System.Collections.Generic.List[PSCustomObject]
        Recommendations  = New-Object System.Collections.Generic.List[PSCustomObject]
        IPAddresses      = New-Object System.Collections.Generic.List[string]
        MailProvider     = ''
        Status           = ''

    }

    # Initialize lists to hold all records
    $RecordList = New-Object System.Collections.Generic.List[PSCustomObject]
    $ValidationFails = New-Object System.Collections.Generic.List[string]
    $ValidationPasses = New-Object System.Collections.Generic.List[string]
    $ValidationWarns = New-Object System.Collections.Generic.List[string]
    $Recommendations = New-Object System.Collections.Generic.List[PSCustomObject]
    $LookupCount = 0
    $AllMechanism = ''
    $Status = ''

    $TypeLookups = New-Object System.Collections.Generic.List[PSCustomObject]
    $IPAddresses = New-Object System.Collections.Generic.List[string]
       
    $DnsQuery = @{
        RecordType = 'TXT'
        Domain     = $Domain
    }

    # Query DNS for SPF Record
    try {
        switch ($PSCmdlet.ParameterSetName) {
            'Lookup' {
                if ($Domain -eq 'Not Specified') {
                    # don't perform lookup if domain is not specified
                }
                else {
                    $Query = Resolve-DnsHttpsQuery @DnsQuery
                    if ($Query.Status -ne 0) {
                        if ($Query.Status -eq 3) {
                            $ValidationFails.Add("FAIL: $Domain - Record does not exist, nxdomain") | Out-Null
                            $Status = 'permerror'
                        }
                        else {
                            $ValidationFails.Add("FAIL: $Domain - Does not resolve an SPF record.") | Out-Null
                            $Status = 'temperror'
                        }
                    }
                    else {
                        $Answer = ($Query.answer | Where-Object { $_.data -match '^v=spf1' })
                        $RecordCount = ($Answer | Measure-Object).count
                        $Record = $Answer.data
                        if ($RecordCount -eq 0) { 
                            $ValidationFails.Add("FAIL: $Domain does not resolve an SPF record.") | Out-Null
                            $Status = 'permerror'
                        }
                        # Check for the correct number of records
                        elseif ($RecordCount -gt 1 -and $Level -eq 'Parent') {
                            $ValidationFails.Add("FAIL: There must only be one SPF record, $RecordCount detected") | Out-Null 
                            $Recommendations.Add([pscustomobject]@{Message = 'Delete one of the records beginning with v=spf1' }) | Out-Null
                            $Status = 'permerror'
                            $Record = $Answer.data[0]
                        }
                    }
                }
            }
            'Manual' {
                if ([string]::IsNullOrEmpty($Domain)) { $Domain = 'Not Specified' }
                $RecordCount = 1
            }
        }
        $SPFResults.Domain = $Domain

        if ($Record -ne '' -and $RecordCount -gt 0) {
            # Split records and parse
            if ($Record -match '^v=spf1(:?\s+(?<Terms>(?![+-~?]all).+?))?(:?\s+(?<AllMechanism>[+-~?]all)(:?\s+(?<Discard>(?!all).+))?)?$') {
                if ($Matches.Terms) {
                    $RecordTerms = $Matches.Terms -split '\s+'
                }
                else {
                    $RecordTerms = @()
                }
                Write-Verbose "########### Record: $Record"

                if ($Level -eq 'Parent' -or $Level -eq 'Redirect') {
                    $AllMechanism = $Matches.AllMechanism
                }

                if ($null -ne $Matches.Discard) {
                    if ($Matches.Discard -notmatch '^exp=(?<Domain>.+)$') {
                        $ValidationWarns.Add("WARN: $Domain - The terms '$($Matches.Discard)' are past the all mechanism and will be discarded") | Out-Null
                        $Recommendations.Add([pscustomobject]@{
                                Message = 'Remove entries following all';
                                Match   = $Matches.Discard
                                Replace = ''
                            }) | Out-Null
                    }
                }

                foreach ($Term in $RecordTerms) {
                    # Redirect modifier
                    if ($Term -match 'redirect=(?<Domain>.+)') {
                        $LookupCount++
                        if ($Record -match '(?<Qualifier>[+-~?])all') {
                            $ValidationFails.Add("FAIL: $Domain - A record with a redirect modifier must not contain an all mechanism, permerror") | Out-Null
                            $Status = 'permerror'
                            $Recommendations.Add([pscustomobject]@{
                                    Message = "Remove the 'all' mechanism from this record.";
                                    Match   = '{0}all' -f $Matches.Qualifier
                                    Replace = ''
                                }) | Out-Null
                        }
                        else {
                            # Follow redirect modifier
                            $RedirectedLookup = Read-SpfRecord -Domain $Matches.Domain -Level 'Redirect'
                            if (($RedirectedLookup | Measure-Object).Count -eq 0) {
                                $ValidationFails.Add("FAIL: $Domain Redirected lookup does not contain a SPF record, permerror") | Out-Null
                                $Status = 'permerror'
                            }
                            else {
                                $RecordList.Add($RedirectedLookup) | Out-Null
                                $AllMechanism = $RedirectedLookup.AllMechanism
                                $ValidationFails.AddRange($RedirectedLookup.ValidationFails) | Out-Null
                                $ValidationWarns.AddRange($RedirectedLookup.ValidationWarns) | Out-Null
                                $ValidationPasses.AddRange($RedirectedLookup.ValidationPasses) | Out-Null
                                $IPAddresses.AddRange($RedirectedLookup.IPAddresses) | Out-Null
                            }
                        }
                        # Record has been redirected, stop evaluating terms
                        break
                    }
                 
                    # Explanation modifier
                    elseif ($Term -match '^exp=(?<Domain>.+)$') {}
            
                    # Include mechanism
                    elseif ($Term -match '^(?<Qualifier>[+-~?])?include:(?<Value>.+)$') {
                        $LookupCount++

                        Write-Verbose "Looking up include $($Matches.Value)"
                        $IncludeLookup = Read-SpfRecord -Domain $Matches.Value -Level 'Include'
                        
                        if (($IncludeLookup | Measure-Object).Count -eq 0) {
                            $ValidationFails.Add("FAIL: $Domain Include lookup does not contain a SPF record, permerror") | Out-Null
                            $Status = 'permerror'
                        }
                        else {
                            $RecordList.Add($IncludeLookup) | Out-Null
                            $ValidationFails.AddRange($IncludeLookup.ValidationFails) | Out-Null
                            $ValidationWarns.AddRange($IncludeLookup.ValidationWarns) | Out-Null
                            $ValidationPasses.AddRange($IncludeLookup.ValidationPasses) | Out-Null
                            $IPAddresses.AddRange($IncludeLookup.IPAddresses) | Out-Null
                        }
                    }

                    # Exists mechanism
                    elseif ($Term -match '^(?<Qualifier>[+-~?])?exists:(?<Value>.+)$') {
                        $LookupCount++
                    }

                    # ip4/ip6 mechanism
                    elseif ($Term -match '^(?<Qualifier>[+-~?])?ip[4,6]:(?<Value>.+)$') {
                        if (-not ($Matches.Qualifier) -or $Matches.Qualifier -eq '+') {
                            $IPAddresses.Add($Matches.Value) | Out-Null
                        }
                    }

                    # Remaining type mechanisms a,mx,ptr
                    elseif ($Term -match '^(?<Qualifier>[+-~?])?(?<RecordType>(?:a|mx|ptr))(?:[:](?<TypeDomain>.+))?$') {
                        $LookupCount++
                    
                        if ($Matches.TypeDomain) {
                            $TypeDomain = $Matches.TypeDomain
                        }
                        else {
                            $TypeDomain = $Domain
                        }      
                    
                        if ($TypeDomain -ne 'Not Specified') {
                            try {
                                $TypeQuery = @{ Domain = $TypeDomain; RecordType = $Matches.RecordType }
                                Write-Verbose "Looking up $($TypeQuery.Domain)"
                                $TypeResult = Resolve-DnsHttpsQuery @TypeQuery
                                
                                if ($Matches.RecordType -eq 'mx') {
                                    $MxCount = 0
                                    foreach ($mx in $TypeResult.Answer.data) {
                                        $MxCount++
                                        $Preference, $MxDomain = $mx -replace '\.$' -split '\s+'                                        
                                        $MxQuery = Resolve-DnsHttpsQuery -Domain $MxDomain
                                        $MxIps = $MxQuery.Answer.data

                                        foreach ($MxIp in $MxIps) {
                                            $IPAddresses.Add($MxIp) | Out-Null
                                        }
                                        
                                        if ($MxCount -gt 10) {
                                            $ValidationWarns.Add("WARN: $Domain - Mechanism 'mx' lookup for $MxDomain exceeded the 10 lookup limit (RFC 7208, Section 4.6.4") | Out-Null
                                            $TypeResult = $null
                                            break
                                        }
                                    }
                                }
                                elseif ($Matches.RecordType -eq 'ptr') {
                                    $ValidationWarns.Add("WARN: $Domain - The mechanism 'ptr' should not be published in an SPF record (RFC 7208, Section 5.5)")
                                }
                            }
                            catch {
                                $TypeResult = $null 
                            }

                            if ($null -eq $TypeResult -or $TypeResult.Status -ne 0) {
                                $Message = "$Domain - Type lookup for mechanism '$($TypeQuery.RecordType)' did not return any results"
                                switch ($Level) {
                                    'Parent' { 
                                        $ValidationFails.Add("FAIL: $Message") | Out-Null
                                        $Status = 'permerror'
                                    }
                                    'Include' { $ValidationWarns.Add("WARN: $Message") | Out-Null }
                                }
                                $Result = $false
                            }
                            else {
                                if ($TypeQuery.RecordType -eq 'mx') {
                                    $Result = $TypeResult.Answer | ForEach-Object { 
                                        $LookupCount++
                                        $_.Data.Split(' ')[1] 
                                    }
                                }
                                else {
                                    $Result = $TypeResult.answer.data
                                }
                            }
                            $TypeLookups.Add(
                                [PSCustomObject]@{
                                    Domain     = $TypeQuery.Domain 
                                    RecordType = $TypeQuery.RecordType
                                    Result     = $Result
                                }
                            ) | Out-Null

                        }
                        else {
                            $ValidationWarns.Add("WARN: No domain specified and mechanism '$Term' does not have one defined. Specify a domain to perform a lookup on this record.") | Out-Null
                        }
                    
                    }
                    elseif ($null -ne $Term) {
                        $ValidationWarns.Add("WARN: $Domain - Unknown term specified '$Term'") | Out-Null
                    }
                }
            }
        }
    }
    catch {}

    # Lookup MX record for expected include information if not supplied
    if ($Level -eq 'Parent' -and $ExpectedInclude -eq '') {
        try {
            #Write-Information $Domain
            $MXRecord = Read-MXRecord -Domain $Domain
            $SPFResults.MailProvider = $MXRecord.MailProvider
            if ($MXRecord.ExpectedInclude -ne '') {
                $ExpectedInclude = $MXRecord.ExpectedInclude
            }

            if ($MXRecord.MailProvider.Name -eq 'Null') {
                if ($Record -eq 'v=spf1 -all') {
                    $ValidationPasses.Add('PASS: SPF record is valid for a Null MX configuration') | Out-Null
                }
                else {
                    $ValidationFails.Add('FAIL: SPF record is not valid for a Null MX configuration. Expected record: "v=spf1 -all"') | Out-Null
                }
            }
        }
        catch {}
    }
        
    # Look for expected include record and report pass or fail
    if ($ExpectedInclude -ne '') {
        if ($RecordList.Domain -notcontains $ExpectedInclude) {
            $ExpectedIncludeSpf = Read-SpfRecord -Domain $ExpectedInclude -Level ExpectedInclude
            $ExpectedIPCount = $ExpectedIncludeSpf.IPAddresses | Measure-Object | Select-Object -ExpandProperty Count
            $FoundIPCount = Compare-Object $IPAddresses $ExpectedIncludeSpf.IPAddresses -IncludeEqual | Where-Object -Property SideIndicator -EQ '==' | Measure-Object | Select-Object -ExpandProperty Count
            if ($ExpectedIPCount -eq $FoundIPCount) {
                $ValidationPasses.Add("PASS: Expected SPF ($ExpectedInclude) IP addresses were found") | Out-Null
            }
            else {
                $ValidationFails.Add("FAIL: Expected SPF include of '$ExpectedInclude' was not found in the SPF record") | Out-Null
            }
        }
        else {
            $ValidationPasses.Add("PASS: Expected SPF record ($ExpectedInclude) was included") | Out-Null
        }
    }

    # Count total lookups
    $LookupCount = $LookupCount + ($RecordList | Measure-Object -Property LookupCount -Sum).Sum
        
    if ($Domain -ne 'Not Specified') {
        # Check legacy SPF type
        $LegacySpfType = Resolve-DnsHttpsQuery -Domain $Domain -RecordType 'SPF'
        if ($null -ne $LegacySpfType -and $LegacySpfType -eq 0) {
            $ValidationWarns.Add("WARN: Domain: $Domain Record Type SPF detected, this is legacy and should not be used. It is recommeded to delete this record. (RFC 7208 Section 14.1)") | Out-Null
        }
    }
    if ($Level -eq 'Parent' -and $RecordCount -gt 0) {
        # Check for the correct all mechanism
        if ($AllMechanism -eq '' -and $Record -ne '') { 
            $ValidationFails.Add('FAIL: All mechanism is missing from SPF record, defaulting to ?all') | Out-Null
            $AllMechanism = '?all' 
        }
        if ($AllMechanism -eq '-all') {
            $ValidationPasses.Add('PASS: SPF record ends in -all') | Out-Null
        }
        elseif ($Record -ne '') {
            $ValidationFails.Add('FAIL: SPF record should end in -all to prevent spamming') | Out-Null 
        }

        # SPF lookup count
        if ($LookupCount -gt 10) { 
            $ValidationFails.Add("FAIL: Lookup count: $LookupCount/10. SPF evaluation will fail with a permerror (RFC 7208 Section 4.6.4)") | Out-Null 
            $Status = 'permerror'
        }
        elseif ($LookupCount -ge 9 -and $LookupCount -le 10) {
            $ValidationWarns.Add("WARN: Lookup count: $LookupCount/10. Excessive lookups can cause the SPF evaluation to fail (RFC 7208 Section 4.6.4)") | Out-Null
        }
        else {
            $ValidationPasses.Add("PASS: Lookup count: $LookupCount/10") | Out-Null
        }

        # Report pass if no PermErrors are found
        if ($Status -ne 'permerror') {
            $ValidationPasses.Add('PASS: No PermError detected in SPF record') | Out-Null
        }

        # Report pass if no errors are found
        if (($ValidationFails | Measure-Object | Select-Object -ExpandProperty Count) -eq 0) {
            $ValidationPasses.Add('PASS: All validation succeeded. No errors detected with SPF record') | Out-Null
        }
    }

    # Set SPF result object
    $SpfResults.Record = $Record
    $SpfResults.RecordCount = $RecordCount
    $SpfResults.LookupCount = $LookupCount
    $SpfResults.AllMechanism = $AllMechanism
    $SpfResults.ValidationPasses = $ValidationPasses
    $SpfResults.ValidationWarns = $ValidationWarns
    $SpfResults.ValidationFails = $ValidationFails
    $SpfResults.RecordList = $RecordList
    $SPFResults.TypeLookups = $TypeLookups
    $SPFResults.IPAddresses = $IPAddresses
    $SPFResults.Status = $Status    

    # Output SpfResults object
    $SpfResults
}

function Read-DmarcPolicy {
    <#
    .SYNOPSIS
    Resolve and validate DMARC policy
    
    .DESCRIPTION
    Query domain for DMARC policy (_dmarc.domain.com) and parse results. Record is checked for issues.
    
    .PARAMETER Domain
    Domain to process DMARC policy
    
    .EXAMPLE
    PS> Read-DmarcPolicy -Domain gmail.com

    Domain           : gmail.com
    Record           : v=DMARC1; p=none; sp=quarantine; rua=mailto:mailauth-reports@google.com
    Version          : DMARC1
    Policy           : none
    SubdomainPolicy  : quarantine
    Percent          : 100
    DkimAlignment    : r
    SpfAlignment     : r
    ReportFormat     : afrf
    ReportInterval   : 86400
    ReportingEmails  : {mailauth-reports@google.com}
    ForensicEmails   : {}
    FailureReport    : 0
    ValidationPasses : {PASS: Aggregate reports are being sent}
    ValidationWarns  : {FAIL: Policy is not being enforced, WARN: Subdomain policy is only partially enforced with quarantine, WARN: Failure report option 0 will only generate a report on both SPF and DKIM misalignment. It is recommended to set this value to 1}
    ValidationFails  : {}
    
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    # Initialize object
    $DmarcAnalysis = [PSCustomObject]@{
        Domain           = $Domain
        Record           = ''
        Version          = ''
        Policy           = ''
        SubdomainPolicy  = ''
        Percent          = 100
        DkimAlignment    = 'r'
        SpfAlignment     = 'r'
        ReportFormat     = 'afrf'
        ReportInterval   = 86400
        ReportingEmails  = New-Object System.Collections.Generic.List[string]
        ForensicEmails   = New-Object System.Collections.Generic.List[string]
        FailureReport    = ''
        ValidationPasses = New-Object System.Collections.Generic.List[string]
        ValidationWarns  = New-Object System.Collections.Generic.List[string]
        ValidationFails  = New-Object System.Collections.Generic.List[string]
    }

    # Validation lists
    $ValidationPasses = New-Object System.Collections.Generic.List[string]
    $ValidationWarns = New-Object System.Collections.Generic.List[string]
    $ValidationFails = New-Object System.Collections.Generic.List[string]

    # Email report domains
    $ReportDomains = New-Object System.Collections.Generic.List[string]

    # Validation ranges
    $PolicyValues = @('none', 'quarantine', 'reject')
    $FailureReportValues = @('0', '1', 'd', 's')
    $ReportFormatValues = @('afrf')

    $RecordCount = 0

    $DnsQuery = @{
        RecordType = 'TXT'
        Domain     = "_dmarc.$Domain"
    }
    
    # Resolve DMARC record

    $Query = Resolve-DnsHttpsQuery @DnsQuery

    $RecordCount = 0
    $Query.Answer | Where-Object { $_.data -match '^v=DMARC1' } | ForEach-Object {
        $DmarcRecord = $_.data
        $DmarcAnalysis.Record = $DmarcRecord
        $RecordCount++  
    }

    if ($Query.Status -ne 0 -or $RecordCount -eq 0) {
        if ($Query.Status -eq 3) {
            $ValidationFails.Add('FAIL: Record does not exist (NXDOMAIN)') | Out-Null
        }
        else {
            $ValidationFails.Add("FAIL: $Domain does not have a DMARC record") | Out-Null
        }
    }
    elseif ($RecordCount -gt 1) {
        $ValidationFails.Add("FAIL: $Domain has multiple DMARC records") | Out-Null
    }

    # Split DMARC record into name/value pairs
    $TagList = New-Object System.Collections.Generic.List[PSCustomObject]
    Foreach ($Element in ($DmarcRecord -split ';').trim()) {
        $Name, $Value = $Element -split '='
        $TagList.Add(
            [PSCustomObject]@{
                Name  = $Name
                Value = $Value
            }
        ) | Out-Null
    }

    # Loop through name/value pairs and set object properties
    $x = 0
    foreach ($Tag in $TagList) {
        switch ($Tag.Name) {
            'v' {
                # REQUIRED: Version
                if ($x -ne 0) { $ValidationFails.Add('FAIL: v=DMARC1 must be at the beginning of the record') | Out-Null }
                if ($Tag.Value -ne 'DMARC1') { $ValidationFails.Add("FAIL: Version must be DMARC1 - found $($Tag.Value)") | Out-Null }
                $DmarcAnalysis.Version = $Tag.Value
            }
            'p' {
                # REQUIRED: Policy
                $DmarcAnalysis.Policy = $Tag.Value
            }
            'sp' {
                # Subdomain policy, defaults to policy record 
                $DmarcAnalysis.SubdomainPolicy = $Tag.Value
            }
            'rua' {
                # Aggregate report emails
                $ReportingEmails = $Tag.Value -split ', '
                $ReportEmailsSet = $false
                foreach ($MailTo in $ReportingEmails) {
                    if ($MailTo -notmatch '^mailto:') { $ValidationFails.Add("FAIL: Aggregate report email must begin with 'mailto:', multiple addresses must be separated by commas - found $($Tag.Value)") | Out-Null }
                    else {
                        $ReportEmailsSet = $true
                        if ($MailTo -match '^mailto:(?<Email>.+@(?<Domain>[^!]+?))(?:!(?<SizeLimit>[0-9]+[kmgt]?))?$') {
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
                foreach ($MailTo in ($Tag.Value -split ', ')) {
                    if ($MailTo -notmatch '^mailto:') { $ValidationFails.Add("FAIL: Forensic report email must begin with 'mailto:', multiple addresses must be separated by commas - found $($Tag.Value)") | Out-Null }
                    else {
                        if ($MailTo -match '^mailto:(?<Email>.+@(?<Domain>[^!]+?))(?:!(?<SizeLimit>[0-9]+[kmgt]?))?$') {
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
                $DmarcAnalysis.FailureReport = $Tag.Value
            } 
            'pct' {
                # Percentage of email to check
                $DmarcAnalysis.Percent = [int]$Tag.Value
            }
            'adkim' {
                # DKIM Alignmenet
                $DmarcAnalysis.DkimAlignment = $Tag.Value
            }
            'aspf' {
                # SPF Alignment
                $DmarcAnalysis.SpfAlignment = $Tag.Value
            }
            'rf' {
                # Report Format
                $DmarcAnalysis.ReportFormat = $Tag.Value
            }
            'ri' {
                # Report Interval
                $DmarcAnalysis.ReportInterval = $Tag.Value
            }
        }
        $x++
    }

    if ($RecordCount -gt 0) {
        # Check report domains for DMARC reporting record
        $ReportDomainCount = $ReportDomains | Measure-Object | Select-Object -ExpandProperty Count
        if ($ReportDomainCount -gt 0) {
            $ReportDomainsPass = $true
            foreach ($ReportDomain in $ReportDomains) {
                $ReportDomainQuery = "$Domain._report._dmarc.$ReportDomain"
                $DnsQuery['Domain'] = $ReportDomainQuery
                $ReportDmarcQuery = Resolve-DnsHttpsQuery @DnsQuery
                $ReportDmarcRecord = $ReportDmarcQuery.Answer.data
                if ($null -eq $ReportDmarcQuery -or $ReportDmarcQuery.Status -ne 0) {
                    $ValidationWarns.Add("WARN: Report DMARC policy for $Domain is missing from $ReportDomain, reports will not be delivered. Expected record: $Domain._report._dmarc.$ReportDomain - Expected value: v=DMARC1; ") | Out-Null
                    $ReportDomainsPass = $false
                }
                elseif ($ReportDmarcRecord -notmatch '^v=DMARC1') {
                    $ValidationWarns.Add("WARN: Report DMARC policy for $Domain is missing from $ReportDomain, reports will not be delivered. Expected record: $Domain._report._dmarc.$ReportDomain - Expected value: v=DMARC1; ") | Out-Null
                    $ReportDomainsPass = $false
                }
            }

            if ($ReportDomainsPass) {
                $ValidationPasses.Add("PASS: All external reporting domains ($($ReportDomains -join ', ')) allow $Domain to send DMARC reports") | Out-Null
            }

        }
        # Check for missing record tags and set defaults
        if ($DmarcAnalysis.Policy -eq '') { $ValidationFails.Add('FAIL: Policy record is missing') | Out-Null }
        if ($DmarcAnalysis.SubdomainPolicy -eq '') { $DmarcAnalysis.SubdomainPolicy = $DmarcAnalysis.Policy }

        # Check policy for errors and best practice
        if ($PolicyValues -notcontains $DmarcAnalysis.Policy) { $ValidationFails.Add("FAIL: Policy must be one of the following - none, quarantine, reject. Found $($Tag.Value)") | Out-Null }
        if ($DmarcAnalysis.Policy -eq 'reject') { $ValidationPasses.Add('PASS: Policy is sufficiently strict') | Out-Null }
        if ($DmarcAnalysis.Policy -eq 'quarantine') { $ValidationWarns.Add('WARN: Policy is only partially enforced with quarantine') | Out-Null }
        if ($DmarcAnalysis.Policy -eq 'none') { $ValidationFails.Add('FAIL: Policy is not being enforced') | Out-Null }

        # Check subdomain policy
        if ($PolicyValues -notcontains $DmarcAnalysis.SubdomainPolicy) { $ValidationFails.Add("FAIL: Subdomain policy must be one of the following - none, quarantine, reject. Found $($DmarcAnalysis.SubdomainPolicy)") | Out-Null }
        if ($DmarcAnalysis.SubdomainPolicy -eq 'reject') { $ValidationPasses.Add('PASS: Subdomain policy is sufficiently strict') | Out-Null }
        if ($DmarcAnalysis.SubdomainPolicy -eq 'quarantine') { $ValidationWarns.Add('WARN: Subdomain policy is only partially enforced with quarantine') | Out-Null }
        if ($DmarcAnalysis.SubdomainPolicy -eq 'none') { $ValidationFails.Add('FAIL: Subdomain policy is not being enforced') | Out-Null }

        # Check percentage - validate range and ensure 100%
        if ($DmarcAnalysis.Percent -lt 100 -and $DmarcAnalysis.Percent -gt 0) { $ValidationWarns.Add('WARN: Not all emails will be processed by the DMARC policy') | Out-Null }
        if ($DmarcAnalysis.Percent -gt 100 -or $DmarcAnalysis.Percent -lt 1) { $ValidationFails.Add('FAIL: Percentage must be between 1 and 100') | Out-Null }

        # Check report format
        if ($ReportFormatValues -notcontains $DmarcAnalysis.ReportFormat) { $ValidationFails.Add("FAIL: The report format '$($DmarcAnalysis.ReportFormat)' is not supported") | Out-Null }
 
        # Check forensic reports and failure options
        $ForensicCount = ($DmarcAnalysis.ForensicEmails | Measure-Object | Select-Object -ExpandProperty Count)
        if ($ForensicCount -eq 0 -and $DmarcAnalysis.FailureReport -ne '') { $ValidationWarns.Add('WARN: Forensic email reports recipients are not defined and failure report options are set. No reports will be sent.') | Out-Null }
        if ($DmarcAnalysis.FailureReport -eq '' -and $null -ne $DmarcRecord) { $DmarcAnalysis.FailureReport = '0' }
        if ($ForensicCount -gt 0) {
            if ($FailureReportValues -notcontains $DmarcAnalysis.FailureReport) { $ValidationFails.Add('FAIL: Failure reporting options must be 0, 1, d or s') | Out-Null }
            if ($DmarcAnalysis.FailureReport -eq '1') { $ValidationPasses.Add('PASS: Failure report option 1 generates forensic reports on SPF or DKIM misalignment') | Out-Null }
            if ($DmarcAnalysis.FailureReport -eq '0') { $ValidationWarns.Add('WARN: Failure report option 0 will only generate a forensic report on both SPF and DKIM misalignment. It is recommended to set this value to 1') | Out-Null }
            if ($DmarcAnalysis.FailureReport -eq 'd') { $ValidationWarns.Add('WARN: Failure report option d will only generate a forensic report on failed DKIM evaluation. It is recommended to set this value to 1') | Out-Null }
            if ($DmarcAnalysis.FailureReport -eq 's') { $ValidationWarns.Add('WARN: Failure report option s will only generate a forensic report on failed SPF evaluation. It is recommended to set this value to 1') | Out-Null }
        }
    }
    
    if ($RecordCount -gt 1) {
        $ValidationWarns.Add('WARN: Multiple DMARC records detected, this may cause unexpected behavior.') | Out-Null
    }

    # Add the validation lists
    $DmarcAnalysis.ValidationPasses = $ValidationPasses
    $DmarcAnalysis.ValidationWarns = $ValidationWarns
    $DmarcAnalysis.ValidationFails = $ValidationFails

    # Return DMARC analysis
    $DmarcAnalysis
}

function Read-DkimRecord {
    <#
    .SYNOPSIS
    Read DKIM record from DNS
    
    .DESCRIPTION
    Validates DKIM records on a domain a selector
    
    .PARAMETER Domain
    Domain to check
    
    .PARAMETER Selectors
    Selector records to check
    
    .PARAMETER MxLookup
    Lookup record based on MX
    
    .EXAMPLE
    PS> Read-DkimRecord -Domain example.com -Selector test

    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Domain,

        [Parameter()]
        [System.Collections.Generic.List[string]]$Selectors = @()
    )

    $MXRecord = $null
    $MinimumSelectorPass = 0
    $SelectorPasses = 0

    $DkimAnalysis = [PSCustomObject]@{
        Domain           = $Domain
        MailProvider     = ''
        Records          = New-Object System.Collections.Generic.List[PSCustomObject]
        ValidationPasses = New-Object System.Collections.Generic.List[string]
        ValidationWarns  = New-Object System.Collections.Generic.List[string]
        ValidationFails  = New-Object System.Collections.Generic.List[string]
    }

    $ValidationPasses = New-Object System.Collections.Generic.List[string]
    $ValidationWarns = New-Object System.Collections.Generic.List[string]
    $ValidationFails = New-Object System.Collections.Generic.List[string]

    if (($Selectors | Measure-Object | Select-Object -ExpandProperty Count) -eq 0) {
        # MX lookup, check for defined selectors
        try {
            $MXRecord = Read-MXRecord -Domain $Domain
            foreach ($Selector in $MXRecord.Selectors) {
                $Selectors.Add($Selector) | Out-Null
            }
            $DkimAnalysis.MailProvider = $MXRecord.MailProvider
            if ($MXRecord.MailProvider.PSObject.Properties.Name -contains 'MinimumSelectorPass') {
                $MinimumSelectorPass = $MXRecord.MailProvider.MinimumSelectorPass
            }
        }
        catch {}
        
        # Explicitly defined DKIM selectors
        if (Test-Path 'Config\DkimSelectors') {
            try {
                Get-ChildItem 'Config\DkimSelectors' -Filter "$($Domain).json" -ErrorAction Stop | ForEach-Object {
                    try {
                        $CustomSelectors = Get-Content $_ | ConvertFrom-Json
                        foreach ($Selector in $CustomSelectors) {
                            $Selectors.Add($Selector) | Out-Null
                        }
                    } 
                    catch {}
                }
            }
            catch {}
        }

        if (($Selectors | Measure-Object | Select-Object -ExpandProperty Count) -eq 0) {
            $ValidationFails.Add("FAIL: $Domain - No selectors provided") | Out-Null
        }
    }
    
    if (($Selectors | Measure-Object | Select-Object -ExpandProperty Count) -gt 0 -and $Selectors -notcontains '') {
        foreach ($Selector in $Selectors) {
            # Initialize object
            $DkimRecord = [PSCustomObject]@{
                Selector         = ''
                Record           = ''
                Version          = ''
                PublicKey        = ''
                PublicKeyInfo    = ''
                KeyType          = ''
                Flags            = ''
                Notes            = ''
                HashAlgorithms   = ''
                ServiceType      = ''
                Granularity      = ''
                UnrecognizedTags = New-Object System.Collections.Generic.List[PSCustomObject]
            }

            $DnsQuery = @{
                RecordType = 'TXT'
                Domain     = "$Selector._domainkey.$Domain"
            }

            $QueryResults = Resolve-DnsHttpsQuery @DnsQuery

            if ($QueryResults -eq '' -or $QueryResults.Status -ne 0) {
                if ($QueryResults.Status -eq 3) {
                    if ($MinimumSelectorPass -eq 0) {
                        $ValidationFails.Add("FAIL: $Selector - Selector record does not exist (NXDOMAIN)") | Out-Null
                    }
                }
                else {
                    $ValidationFails.Add("FAIL: $Selector - DKIM record is missing, check the selector and try again") | Out-Null
                }
                $Record = ''
            }
            else {
                $QueryData = ($QueryResults.Answer).data | Where-Object { $_ -match '^v=DKIM1' }
                if (( $QueryData | Measure-Object).Count -gt 1) {
                    $Record = $QueryData[-1]
                }
                else {
                    $Record = $QueryData
                }
            }
            $DkimRecord.Selector = $Selector

            if ($null -eq $Record) { $Record = '' }
            $DkimRecord.Record = $Record

            # Split DKIM record into name/value pairs
            $TagList = New-Object System.Collections.Generic.List[PSCustomObject]
            Foreach ($Element in ($Record -split ';')) {
                if ($Element -ne '') {
                    $Name, $Value = $Element.trim() -split '='
                    $TagList.Add(
                        [PSCustomObject]@{
                            Name  = $Name
                            Value = $Value
                        }
                    ) | Out-Null
                }
            }
            
            # Loop through name/value pairs and set object properties
            $x = 0
            foreach ($Tag in $TagList) {
                switch ($Tag.Name) {
                    'v' {
                        # REQUIRED: Version
                        if ($x -ne 0) { $ValidationFails.Add("FAIL: $Selector - v=DKIM1 must be at the beginning of the record") | Out-Null }
                        if ($Tag.Value -ne 'DKIM1') { $ValidationFails.Add("FAIL: $Selector - Version must be DKIM1 - found $($Tag.Value)") | Out-Null }
                        $DkimRecord.Version = $Tag.Value
                    }
                    'p' {
                        # REQUIRED: Public Key
                        if ($Tag.Value -ne '') {
                            $DkimRecord.PublicKey = "-----BEGIN PUBLIC KEY-----`n {0}`n-----END PUBLIC KEY-----" -f $Tag.Value
                            $DkimRecord.PublicKeyInfo = Get-RsaPublicKeyInfo -EncodedString $Tag.Value
                        }
                        else {
                            if ($MXRecord.MailProvider.Name -eq 'Null') {
                                $ValidationPasses.Add("PASS: $Selector - DKIM configuration is valid for a Null MX record configuration") | Out-Null
                            }
                            else {
                                $ValidationFails.Add("FAIL: $Selector - No public key specified for DKIM record or key revoked") | Out-Null 
                            }
                        }
                    }
                    'k' {
                        $DkimRecord.KeyType = $Tag.Value
                    }
                    't' {
                        $DkimRecord.Flags = $Tag.Value
                    }
                    'n' {
                        $DkimRecord.Notes = $Tag.Value
                    }
                    'h' {
                        $DkimRecord.HashAlgorithms = $Tag.Value
                    }
                    's' {
                        $DkimRecord.ServiceType = $Tag.Value
                    }
                    'g' {
                        $DkimRecord.Granularity = $Tag.Value
                    }
                    default {
                        $DkimRecord.UnrecognizedTags.Add($Tag) | Out-Null
                    }
                }
                $x++
            }

            if ($Record -ne '') {
                if ($DkimRecord.KeyType -eq '') { $DkimRecord.KeyType = 'rsa' }

                if ($DkimRecord.HashAlgorithms -eq '') { $DkimRecord.HashAlgorithms = 'all' }

                $UnrecognizedTagCount = $UnrecognizedTags | Measure-Object | Select-Object -ExpandProperty Count
                if ($UnrecognizedTagCount -gt 0) {
                    $TagString = ($UnrecognizedTags | ForEach-Object { '{0}={1}' -f $_.Tag, $_.Value }) -join ', '
                    $ValidationWarns.Add("WARN: $Selector - $UnrecognizedTagCount tag(s) detected in DKIM record. This can cause issues with some mailbox providers. Tags: $TagString")
                }
                if ($DkimRecord.Flags -eq 'y') {
                    $ValidationWarns.Add("WARN: $Selector - This flag 't=y' indicates that this domain is testing mode currently. If DKIM is fully deployed, this flag should be changed to t=s unless subdomaining is required.") | Out-Null
                }

                if ($DkimRecord.PublicKeyInfo.SignatureAlgorithm -ne $DkimRecord.KeyType -and $MXRecord.MailProvider.Name -ne 'Null') {
                    $ValidationWarns.Add("WARN: $Selector - Key signature algorithm $($DkimRecord.PublicKeyInfo.SignatureAlgorithm) does not match $($DkimRecord.KeyType)") | Out-Null
                }

                if ($DkimRecord.PublicKeyInfo.KeySize -lt 1024 -and $MXRecord.MailProvider.Name -ne 'Null') {
                    $ValidationFails.Add("FAIL: $Selector - Key size is less than 1024 bit, found $($DkimRecord.PublicKeyInfo.KeySize)") | Out-Null
                }
                else {
                    if ($MXRecord.MailProvider.Name -ne 'Null') {
                        $ValidationPasses.Add("PASS: $Selector - DKIM key validation succeeded ($($DkimRecord.PublicKeyInfo.KeySize) bit)") | Out-Null
                    }
                    $SelectorPasses++
                }

                ($DkimAnalysis.Records).Add($DkimRecord) | Out-Null

                if (($ValidationFails | Measure-Object | Select-Object -ExpandProperty Count) -eq 0) {
                    $ValidationPasses.Add("PASS: $Selector - No errors detected with DKIM record") | Out-Null
                }
            }      
        }
    }
    else {
        $ValidationWarns.Add('WARN: No DKIM selectors provided') | Out-Null
    }

    if ($MinimumSelectorPass -gt 0 -and $SelectorPasses -eq 0) {
        $ValidationFails.Add(('FAIL: Minimum number of selector record passes were not met {0}/{1}' -f $SelectorPasses, $MinimumSelectorPass)) | Out-Null
    }
    elseif ($MinimumSelectorPass -gt 0 -and $SelectorPasses -ge $MinimumSelectorPass) {
        $ValidationPasses.Add(('PASS: Minimum number of selector record passes were met {0}/{1}' -f $SelectorPasses, $MinimumSelectorPass))
    }

    # Collect validation results
    $DkimAnalysis.ValidationPasses = $ValidationPasses
    $DkimAnalysis.ValidationWarns = $ValidationWarns
    $DkimAnalysis.ValidationFails = $ValidationFails

    # Return analysis
    $DkimAnalysis
}

function Read-WhoisRecord {
    <#
    .SYNOPSIS
    Reads Whois record data for queried information
    
    .DESCRIPTION
    Connects to top level registrar servers (IANA, ARIN) and performs recursion to find Whois data
    
    .PARAMETER Query
    Whois query to perform (e.g. microsoft.com)
    
    .PARAMETER Server
    Whois server to query, defaults to whois.iana.org
    
    .PARAMETER Port
    Whois server port, default 43
    
    .EXAMPLE
    PS> Read-WhoisRecord -Query microsoft.com
    
    #>
    [CmdletBinding()]
    param (
        [Parameter (Position = 0, Mandatory = $true)]
        [String]$Query,
        [String]$Server = 'whois.iana.org',
        $Port = 43
    )
    $HasReferral = $false

    # Top level referring servers, IANA and ARIN
    $TopLevelReferrers = @('whois.iana.org', 'whois.arin.net')

    # Record Pattern Matching
    $ServerPortRegex = '(?<refsvr>[^:\r\n]+)(:(?<port>\d+))?'
    $ReferralMatch = @{
        'ReferralServer'         = "whois://$ServerPortRegex"
        'Whois Server'           = $ServerPortRegex
        'Registrar Whois Server' = $ServerPortRegex
        'refer'                  = $ServerPortRegex
        'remarks'                = '(?<refsvr>whois\.[0-9a-z\-\.]+\.[a-z]{2,})(:(?<port>\d+))?'
    }

    # List of properties for Registrars
    $RegistrarProps = @(
        'Registrar'
    )

    # Whois parser, generic Property: Value format with some multi-line support and comment handlers
    $WhoisRegex = '^(?!(?:%|>>>|-+|#|[*]))[^\S\n]*(?<PropName>.+?):(?:[\r\n]+)?(:?(?!([0-9]|[/]{2}))[^\S\r\n]*(?<PropValue>.+))?$'

    # TCP Client for Whois
    $Client = New-Object System.Net.Sockets.TcpClient($Server, 43)
    try {
        # Open TCP connection and send query
        $Stream = $Client.GetStream()
        $ReferralServers = New-Object System.Collections.Generic.List[string]
        $ReferralServers.Add($Server) | Out-Null

        # WHOIS query to send
        $Data = [System.Text.Encoding]::Ascii.GetBytes("$Query`r`n")
        $Stream.Write($Data, 0, $data.length)

        # Read response from stream
        $Reader = New-Object System.IO.StreamReader $Stream, [System.Text.Encoding]::ASCII
        $Raw = $Reader.ReadToEnd()
        
        # Split comments and parse raw whois results
        $data, $comment = $Raw -split '(>>>|\n\s+--)'
        $PropMatches = [regex]::Matches($data, $WhoisRegex, ([System.Text.RegularExpressions.RegexOptions]::MultiLine, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase))

        # Hold property count in hashtable for auto increment
        $PropertyCounts = @{}

        # Create ordered list for properties
        $Results = [ordered]@{}
        foreach ($PropMatch in $PropMatches) { 
            $PropName = $PropMatch.Groups['PropName'].value
            if ($Results.Contains($PropName)) {
                $PropertyCounts.$PropName++
                $PropName = '{0}{1}' -f $PropName, $PropertyCounts.$PropName
                $Results[$PropName] = $PropMatch.Groups['PropValue'].value.trim()
            }
            else {
                $Results[$PropName] = $PropMatch.Groups['PropValue'].value.trim()
                $PropertyCounts.$PropName = 0
            }
        }

        foreach ($RegistrarProp in $RegistrarProps) {
            if ($Results.Contains($RegistrarProp)) {
                $Results._Registrar = $Results.$RegistrarProp
                break
            }
        }

        # Store raw results and query metadata
        $Results._Raw = $Raw
        $Results._ReferralServers = New-Object System.Collections.Generic.List[string]
        $Results._Query = $Query
        $LastResult = $Results

        # Loop through keys looking for referral server match
        foreach ($Key in $ReferralMatch.Keys) {
            if ([bool]($Results.Keys -match $Key)) {
                if ($Results.$Key -match $ReferralMatch.$Key) {
                    $ReferralServer = $Matches.refsvr
                    if ($Server -ne $ReferralServer) {
                        if ($Matches.port) { $Port = $Matches.port }
                        else { $Port = 43 }
                        $HasReferral = $true
                        break
                    }
                }
            }
        }

        # Recurse through referrals
        if ($HasReferral) {    
            if ($Server -ne $ReferralServer) {
                $LastResult = $Results
                $Results = Get-Whois -Query $Query -Server $ReferralServer -Port $Port
                if ($Results._Raw -Match '(No match|Not Found)' -and $TopLevelReferrers -notcontains $Server) { 
                    $Results = $LastResult 
                }
                else {
                    foreach ($s in $Results._ReferralServers) {
                        $ReferralServers.Add($s) | Out-Null
                    }
                }
                
            }
        } 
        else {
            if ($Results._Raw -Match '(No match|Not Found)') {
                $first, $newquery = ($Query -split '\.')
                if (($newquery | Measure-Object).Count -gt 1) {
                    $Query = $newquery -join '.'
                    $Results = Get-Whois -Query $Query -Server $Server -Port $Port
                    foreach ($s in $Results._ReferralServers) {
                        $ReferralServers.Add($s) | Out-Null
                    }
                }
            }
        }
    }
    catch {
        Write-Error $_.Exception.Message
    }
    finally {
        IF ($Stream) {
            $Stream.Close()
            $Stream.Dispose()
        }
    }

    # Collect referral server list
    $Results._ReferralServers = $ReferralServers
    
    # Convert to json and back to preserve object order
    $WhoisResults = $Results | ConvertTo-Json | ConvertFrom-Json

    # Return Whois results as PSObject
    $WhoisResults
}

function Get-RsaPublicKeyInfo {
    <#
    .SYNOPSIS
    Gets RSA public key info from Base64 string
    
    .DESCRIPTION
    Decodes RSA public key information for validation. Uses a c# library to decode base64 data.
    
    .PARAMETER EncodedString
    Base64 encoded public key string
    
    .EXAMPLE
    PS> Get-RsaPublicKeyInfo -EncodedString <base64 string>
    
    LegalKeySizes                           KeyExchangeAlgorithm SignatureAlgorithm KeySize
    -------------                           -------------------- ------------------ -------
    {System.Security.Cryptography.KeySizes} RSA                  RSA                   2048
    
    .NOTES
    Obtained C# code from https://github.com/sevenTiny/Bamboo/blob/b5503b5597383ca6085ceb4aa5fa054918a4bd73/10-Code/SevenTiny.Bantina/Security/RSACommon.cs
    #>
    Param(
        [Parameter(Mandatory = $true)]
        $EncodedString
    )
    $source = @'
/*********************************************************
 * CopyRight: 7TINY CODE BUILDER. 
 * Version: 5.0.0
 * Author: 7tiny
 * Address: Earth
 * Create: 2018-04-08 21:54:19
 * Modify: 2018-04-08 21:54:19
 * E-mail: dong@7tiny.com | sevenTiny@foxmail.com 
 * GitHub: https://github.com/sevenTiny 
 * Personal web site: http://www.7tiny.com 
 * Technical WebSit: http://www.cnblogs.com/7tiny/ 
 * Description: 
 * Thx , Best Regards ~
 *********************************************************/
using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace SevenTiny.Bantina.Security {
    public static class RSACommon {
        public static RSA CreateRsaProviderFromPublicKey(string publicKeyString)
        {
            // encoded OID sequence for  PKCS #1 rsaEncryption szOID_RSA_RSA = "1.2.840.113549.1.1.1"
            byte[] seqOid = { 0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00 };
            byte[] seq = new byte[15];

            var x509Key = Convert.FromBase64String(publicKeyString);

            // ---------  Set up stream to read the asn.1 encoded SubjectPublicKeyInfo blob  ------
            using (MemoryStream mem = new MemoryStream(x509Key))
            {
                using (BinaryReader binr = new BinaryReader(mem))  //wrap Memory Stream with BinaryReader for easy reading
                {
                    byte bt = 0;
                    ushort twobytes = 0;

                    twobytes = binr.ReadUInt16();
                    if (twobytes == 0x8130) //data read as little endian order (actual data order for Sequence is 30 81)
                        binr.ReadByte();    //advance 1 byte
                    else if (twobytes == 0x8230)
                        binr.ReadInt16();   //advance 2 bytes
                    else
                        return null;

                    seq = binr.ReadBytes(15);       //read the Sequence OID
                    if (!CompareBytearrays(seq, seqOid))    //make sure Sequence for OID is correct
                        return null;

                    twobytes = binr.ReadUInt16();
                    if (twobytes == 0x8103) //data read as little endian order (actual data order for Bit String is 03 81)
                        binr.ReadByte();    //advance 1 byte
                    else if (twobytes == 0x8203)
                        binr.ReadInt16();   //advance 2 bytes
                    else
                        return null;

                    bt = binr.ReadByte();
                    if (bt != 0x00)     //expect null byte next
                        return null;

                    twobytes = binr.ReadUInt16();
                    if (twobytes == 0x8130) //data read as little endian order (actual data order for Sequence is 30 81)
                        binr.ReadByte();    //advance 1 byte
                    else if (twobytes == 0x8230)
                        binr.ReadInt16();   //advance 2 bytes
                    else
                        return null;

                    twobytes = binr.ReadUInt16();
                    byte lowbyte = 0x00;
                    byte highbyte = 0x00;

                    if (twobytes == 0x8102) //data read as little endian order (actual data order for Integer is 02 81)
                        lowbyte = binr.ReadByte();  // read next bytes which is bytes in modulus
                    else if (twobytes == 0x8202)
                    {
                        highbyte = binr.ReadByte(); //advance 2 bytes
                        lowbyte = binr.ReadByte();
                    }
                    else
                        return null;
                    byte[] modint = { lowbyte, highbyte, 0x00, 0x00 };   //reverse byte order since asn.1 key uses big endian order
                    int modsize = BitConverter.ToInt32(modint, 0);

                    int firstbyte = binr.PeekChar();
                    if (firstbyte == 0x00)
                    {   //if first byte (highest order) of modulus is zero, don't include it
                        binr.ReadByte();    //skip this null byte
                        modsize -= 1;   //reduce modulus buffer size by 1
                    }

                    byte[] modulus = binr.ReadBytes(modsize);   //read the modulus bytes

                    if (binr.ReadByte() != 0x02)            //expect an Integer for the exponent data
                        return null;
                    int expbytes = (int)binr.ReadByte();        // should only need one byte for actual exponent data (for all useful values)
                    byte[] exponent = binr.ReadBytes(expbytes);

                    // ------- create RSACryptoServiceProvider instance and initialize with public key -----
                    var rsa = System.Security.Cryptography.RSA.Create();
                    RSAParameters rsaKeyInfo = new RSAParameters
                    {
                        Modulus = modulus,
                        Exponent = exponent
                    };
                    rsa.ImportParameters(rsaKeyInfo);

                    return rsa;
                }
            }
        }
        private static bool CompareBytearrays(byte[] a, byte[] b)
        {
            if (a.Length != b.Length)
                return false;
            int i = 0;
            foreach (byte c in a)
            {
                if (c != b[i])
                    return false;
                i++;
            }
            return true;
        }
    }
}
'@
    if (!('SevenTiny.Bantina.Security.RSACommon' -as [type])) {
        Add-Type -TypeDefinition $source -Language CSharp
    }

    # Return RSA Public Key information
    [SevenTiny.Bantina.Security.RSACommon]::CreateRsaProviderFromPublicKey($EncodedString)
}
