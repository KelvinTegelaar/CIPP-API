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

    try {
        $ConfigTable = Get-CippTable -tablename Config
        $Filter = "PartitionKey eq 'Domains' and RowKey eq 'Domains'"
        $Config = Get-AzDataTableEntity @ConfigTable -Filter $Filter

        $ValidResolvers = @('Google', 'CloudFlare', 'Quad9')
        if ($ValidResolvers -contains $Config.Resolver) {
            $Resolver = $Config.Resolver
        }
        else {
            $Resolver = 'Google'
            $Config = @{
                PartitionKey = 'Domains'
                RowKey       = 'Domains'
                Resolver     = $Resolver
            }
            Add-AzDataTableEntity @ConfigTable -Entity $Config -Force
        }
    }
    catch {
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
        'Quad9' {
            $BaseUri = 'https://dns9.quad9.net:5053/dns-query'
            $QueryTemplate = '{0}?name={1}&type={2}'
        }
    }

    $Headers = @{
        'accept' = 'application/dns-json'
    }

    $Uri = $QueryTemplate -f $BaseUri, $Domain, $RecordType

    $Results = Invoke-RestMethod -Uri $Uri -Headers $Headers -ErrorAction Stop
    
    if ($Resolver -eq 'Cloudflare' -or $Resolver -eq 'Quad9' -and $RecordType -eq 'txt' -and $Results.Answer) {
        $Results.Answer | ForEach-Object {
            $_.data = $_.data -replace '"' -replace '\s+', ' '
        }
        $Results.Answer = $Results.Answer | Where-Object { $_.type -eq 16 } 
    }
    
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
    ValidationPasses : {example.com - DNSSEC enabled and validated}
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
        ValidationPasses = [System.Collections.Generic.List[string]]::new()
        ValidationWarns  = [System.Collections.Generic.List[string]]::new()
        ValidationFails  = [System.Collections.Generic.List[string]]::new()
        Keys             = [System.Collections.Generic.List[string]]::new()
    }
    $ValidationPasses = [System.Collections.Generic.List[string]]::new()
    $ValidationFails = [System.Collections.Generic.List[string]]::new()

    $DnsQuery = @{
        RecordType = 'dnskey'
        Domain     = $Domain
    }

    $Result = Resolve-DnsHttpsQuery @DnsQuery -ErrorAction Stop
    if ($Result.Status -eq 2 -and $Result.AD -eq $false) {
        $ValidationFails.Add('DNSSEC Validation failed.') | Out-Null
    }
    else {
        $RecordCount = ($Result.Answer.data | Measure-Object).Count
        if ($null -eq $Result) {
            $ValidationFails.Add('DNSSEC is not set up for this domain.') | Out-Null
        }
        else {
            if ($Result.Status -eq 3) {
                $ValidationFails.Add('DNSSEC is not set up for this domain.') | Out-Null
            }
            elseif ($RecordCount -gt 0) {
                if ($Result.AD -eq $false) {
                    $ValidationFails.Add('DNSSEC is enabled, but the DNS query response was not validated. Ensure DNSSEC has been enabled on your domain provider.') | Out-Null
                }
                else {
                    $ValidationPasses.Add('DNSSEC is enabled and validated for this domain.') | Out-Null
                }
                $DSResults.Keys = $Result.answer.data
            }
            else {
                $ValidationFails.Add('DNSSEC is not set up for this domain.') | Out-Null
            }
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
        Records          = [System.Collections.Generic.List[string]]::new()
        ValidationPasses = [System.Collections.Generic.List[string]]::new()
        ValidationWarns  = [System.Collections.Generic.List[string]]::new()
        ValidationFails  = [System.Collections.Generic.List[string]]::new()
        NameProvider     = ''
    }
    $ValidationPasses = [System.Collections.Generic.List[string]]::new()
    $ValidationFails = [System.Collections.Generic.List[string]]::new()

    $DnsQuery = @{
        RecordType = 'ns'
        Domain     = $Domain
    }
 
    $NSResults.Domain = $Domain

    try {
        $Result = Resolve-DnsHttpsQuery @DnsQuery -ErrorAction Stop
    }
    catch { $Result = $null }
    if ($Result.Status -eq 2 -and $Result.AD -eq $false) {
        $ValidationFails.Add('DNSSEC Validation failed.') | Out-Null
    }
    elseif ($Result.Status -ne 0 -or -not ($Result.Answer)) {
        $ValidationFails.Add('No nameservers found for this domain.') | Out-Null
        $NSRecords = $null
    }
    else {
        $NSRecords = $Result.Answer.data
        $ValidationPasses.Add('Nameserver record is present.') | Out-Null
        $NSResults.Records = @($NSRecords)
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
        Records          = [System.Collections.Generic.List[object]]::new()
        ValidationPasses = [System.Collections.Generic.List[string]]::new()
        ValidationWarns  = [System.Collections.Generic.List[string]]::new()
        ValidationFails  = [System.Collections.Generic.List[string]]::new()
        MailProvider     = ''
        ExpectedInclude  = ''
        Selectors        = ''
    }
    $ValidationPasses = [System.Collections.Generic.List[string]]::new()
    $ValidationFails = [System.Collections.Generic.List[string]]::new()

    $DnsQuery = @{
        RecordType = 'mx'
        Domain     = $Domain
    }

    Set-Location (Get-Item $PSScriptRoot).FullName
    
    $NoMxValidation = 'There are no mail exchanger records for this domain. If you do not want to receive mail for this domain use a Null MX record of . with a priority 0 (RFC 7505).'
 
    $MXResults.Domain = $Domain

    try {
        $Result = Resolve-DnsHttpsQuery @DnsQuery -ErrorAction Stop
    }
    catch { $Result = $null }
    if ($Result.Status -eq 2 -and $Result.AD -eq $false) {
        $ValidationFails.Add('DNSSEC validation failed.') | Out-Null
    }
    elseif ($Result.Status -ne 0 -or -not ($Result.Answer)) {
        if ($Result.Status -eq 3) {
            $ValidationFails.Add($NoMxValidation) | Out-Null
            $MXResults.MailProvider = Get-Content 'MailProviders\Null.json' | ConvertFrom-Json
            $MXResults.Selectors = $MXRecords.MailProvider.Selectors
        }
        else {
            $ValidationFails.Add($NoMxValidation) | Out-Null
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
        $ValidationPasses.Add('Mail exchanger records record(s) are present for this domain.') | Out-Null
        $MXRecords = $MXRecords | Sort-Object -Property Priority

        # Attempt to identify mail provider based on MX record
        if (Test-Path 'MailProviders') {
            $ReservedVariables = @{
                'DomainNameDashNotation' = $Domain -replace '\.', '-'
            }
            if ($MXRecords.Hostname -eq '') {
                $ValidationFails.Add($NoMxValidation) | Out-Null
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
                                    $ReplaceList = [System.Collections.Generic.List[string]]::new()
                                    foreach ($Var in $Provider.SpfReplace) { 
                                        if ($ReservedVariables.Keys -contains $Var) {
                                            $ReplaceList.Add($ReservedVariables.$Var) | Out-Null
                                        } 
                                        else {
                                            $ReplaceList.Add($Matches.$Var) | Out-Null
                                        }
                                    }

                                    $ExpectedInclude = $Provider.SpfInclude -f ($ReplaceList -join ', ')
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
    $MXResults.ValidationPasses = @($ValidationPasses)
    $MXResults.ValidationFails = @($ValidationFails)
    $MXResults.Records = @($MXResults.Records)
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
    ValidationPasses : {Expected SPF record was included, No PermError detected in SPF record}
    ValidationWarns  : {}
    ValidationFails  : {SPF record should end in -all to prevent spamming}
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
    $SpfResults = [PSCustomObject]@{
        Domain            = ''
        Record            = ''
        RecordCount       = 0
        LookupCount       = 0
        AllMechanism      = ''
        ValidationPasses  = [System.Collections.Generic.List[string]]::new()
        ValidationWarns   = [System.Collections.Generic.List[string]]::new()
        ValidationFails   = [System.Collections.Generic.List[string]]::new()
        RecordList        = [System.Collections.Generic.List[object]]::new()   
        TypeLookups       = [System.Collections.Generic.List[object]]::new()
        Recommendations   = [System.Collections.Generic.List[object]]::new()
        RecommendedRecord = ''
        IPAddresses       = [System.Collections.Generic.List[string]]::new()
        MailProvider      = ''
        Status            = ''

    }

  

    # Initialize lists to hold all records
    $RecordList = [System.Collections.Generic.List[object]]::new()
    $ValidationFails = [System.Collections.Generic.List[string]]::new()
    $ValidationPasses = [System.Collections.Generic.List[string]]::new()
    $ValidationWarns = [System.Collections.Generic.List[string]]::new()
    $Recommendations = [System.Collections.Generic.List[object]]::new()
    $LookupCount = 0
    $AllMechanism = ''
    $Status = ''
    $RecommendedRecord = ''

    $TypeLookups = [System.Collections.Generic.List[object]]::new()
    $IPAddresses = [System.Collections.Generic.List[string]]::new()
       
    $DnsQuery = @{
        RecordType = 'TXT'
        Domain     = $Domain
    }

    $NoSpfValidation = 'No SPF record was detected for this domain.'

    # Query DNS for SPF Record
    try {
        switch ($PSCmdlet.ParameterSetName) {
            'Lookup' {
                if ($Domain -eq 'Not Specified') {
                    # don't perform lookup if domain is not specified
                }
                else {
                    $Query = Resolve-DnsHttpsQuery @DnsQuery -ErrorAction Stop
                    if ($Query.Status -eq 2 -and $Query.AD -eq $false) {
                        $ValidationFails.Add('DNSSEC validation failed.') | Out-Null
                    }
                    elseif ($Query.Status -ne 0) {
                        if ($Query.Status -eq 3) {
                            $ValidationFails.Add($NoSpfValidation) | Out-Null
                            $Status = 'permerror'
                        }
                        else {
                            Write-Host $Query
                            $ValidationFails.Add($NoSpfValidation) | Out-Null
                            $Status = 'temperror'
                        }
                    }
                    else {
                        
                        $Answer = ($Query.answer | Where-Object { $_.data -match '^v=spf1' })
                        $RecordCount = ($Answer.data | Measure-Object).count
                        $Record = $Answer.data
                        if ($RecordCount -eq 0) { 
                            $ValidationFails.Add($NoSpfValidation) | Out-Null
                            $Status = 'permerror'
                        }
                        # Check for the correct number of records
                        elseif ($RecordCount -gt 1 -and $Level -eq 'Parent') {
                            $ValidationFails.Add("There must only be one SPF record per domain, we found $RecordCount.") | Out-Null 
                            $Recommendations.Add([pscustomobject]@{
                                    Message = 'Delete one of the records beginning with v=spf1'
                                    Match   = '' 
                                }) | Out-Null
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
        $SpfResults.Domain = $Domain

        if ($Record -ne '' -and $RecordCount -gt 0) {
            # Split records and parse
            if ($Record -match '^v=spf1(:?\s+(?<Terms>(?![+-~?]all).+?))?(:?\s+(?<AllMechanism>[+-~?]all)(:?\s+(?<Discard>(?!all).+))?)?$') {
                if ($Matches.Terms) {
                    $RecordTerms = $Matches.Terms -split '\s+'
                }
                else {
                    $RecordTerms = @()
                }
                Write-Verbose "########### RECORD: $Record"

                if ($Level -eq 'Parent' -or $Level -eq 'Redirect') {
                    $AllMechanism = $Matches.AllMechanism
                }

                if ($null -ne $Matches.Discard) {
                    if ($Matches.Discard -notmatch '^exp=(?<Domain>.+)$') {
                        $ValidationWarns.Add("The terms '$($Matches.Discard)' are past the all mechanism and will be discarded.") | Out-Null
                        $Recommendations.Add([pscustomobject]@{
                                Message = 'Remove entries following all';
                                Match   = $Matches.Discard
                                Replace = ''
                            }) | Out-Null
                    }
                }

                foreach ($Term in $RecordTerms) {
                    Write-Verbose "TERM $Term"
                    # Redirect modifier
                    if ($Term -match 'redirect=(?<Domain>.+)') {
                        Write-Verbose '-----REDIRECT-----'
                        $LookupCount++
                        if ($Record -match '(?<Qualifier>[+-~?])all') {
                            $ValidationFails.Add('A record with a redirect modifier must not contain an all mechanism. This will result in a failure.') | Out-Null
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
                                $ValidationFails.Add("$Domain Redirected lookup does not contain a SPF record, this will result in a failure.") | Out-Null
                                $Status = 'permerror'
                            }
                            else {
                                $RecordList.Add($RedirectedLookup) | Out-Null
                                $AllMechanism = $RedirectedLookup.AllMechanism
                                $ValidationFails.AddRange([string[]]$RedirectedLookup.ValidationFails) | Out-Null
                                $ValidationWarns.AddRange([string[]]$RedirectedLookup.ValidationWarns) | Out-Null
                                $ValidationPasses.AddRange([string[]]$RedirectedLookup.ValidationPasses) | Out-Null
                                $IPAddresses.AddRange([string[]]$RedirectedLookup.IPAddresses) | Out-Null
                            }
                        }
                        # Record has been redirected, stop evaluating terms
                        break
                    }
                 
                    # Explanation modifier
                    elseif ($Term -match '^exp=(?<Domain>.+)$') { Write-Verbose '-----EXP-----' }
            
                    # Include mechanism
                    elseif ($Term -match '^(?<Qualifier>[+-~?])?include:(?<Value>.+)$') {
                        $LookupCount++
                        Write-Verbose '-----INCLUDE-----'
                        Write-Verbose "Looking up include $($Matches.Value)"
                        $IncludeLookup = Read-SpfRecord -Domain $Matches.Value -Level 'Include'
                        
                        if ([string]::IsNullOrEmpty($IncludeLookup.Record) -and $Level -eq 'Parent') {
                            Write-Verbose '-----END INCLUDE (SPF MISSING)-----'
                            $ValidationFails.Add("Include lookup for $($Matches.Value) does not contain a SPF record, this will result in a failure.") | Out-Null
                            $Status = 'permerror'
                        }
                        else {
                            Write-Verbose '-----END INCLUDE (SPF FOUND)-----'
                            $RecordList.Add($IncludeLookup) | Out-Null
                            $ValidationFails.AddRange([string[]]$IncludeLookup.ValidationFails) | Out-Null
                            $ValidationWarns.AddRange([string[]]$IncludeLookup.ValidationWarns) | Out-Null
                            $ValidationPasses.AddRange([string[]]$IncludeLookup.ValidationPasses) | Out-Null
                            $IPAddresses.AddRange([string[]]$IncludeLookup.IPAddresses) | Out-Null
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
                                $TypeResult = Resolve-DnsHttpsQuery @TypeQuery -ErrorAction Stop
                                
                                if ($Matches.RecordType -eq 'mx') {
                                    $MxCount = 0
                                    foreach ($mx in $TypeResult.Answer.data) {
                                        $MxCount++
                                        $Preference, $MxDomain = $mx -replace '\.$' -split '\s+'                                        
                                        $MxQuery = Resolve-DnsHttpsQuery -Domain $MxDomain -ErrorAction Stop
                                        $MxIps = $MxQuery.Answer.data

                                        foreach ($MxIp in $MxIps) {
                                            $IPAddresses.Add($MxIp) | Out-Null
                                        }
                                        
                                        if ($MxCount -gt 10) {
                                            $ValidationWarns.Add("$Domain - Mechanism 'mx' lookup for $MxDomain has exceeded the 10 lookup limit(RFC 7208, Section 4.6.4).") | Out-Null
                                            $TypeResult = $null
                                            break
                                        }
                                    }
                                }
                                elseif ($Matches.RecordType -eq 'ptr') {
                                    $ValidationWarns.Add("$Domain - The mechanism 'ptr' should not be published in an SPF record (RFC 7208, Section 5.5)")
                                }
                            }
                            catch {
                                $TypeResult = $null 
                            }

                            if ($null -eq $TypeResult -or $TypeResult.Status -ne 0) {
                                $Message = "$Domain - Type lookup for the mechanism '$($TypeQuery.RecordType)' did not return any results."
                                switch ($Level) {
                                    'Parent' { 
                                        $ValidationFails.Add("$Message") | Out-Null
                                        $Status = 'permerror'
                                    }
                                    'Include' { $ValidationWarns.Add("$Message") | Out-Null }
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
                            $ValidationWarns.Add("No domain was specified and mechanism '$Term' does not have one defined. Specify a domain to perform a lookup on this record.") | Out-Null
                        }
                    
                    }
                    elseif ($null -ne $Term) {
                        $ValidationWarns.Add("$Domain - Unknown term specified '$Term'") | Out-Null
                    }
                }
            }
        }
    }
    catch {
        Write-Verbose "EXCEPTION: $($_.Exception.Message)"
    }
    
    # Lookup MX record for expected include information if not supplied
    if ($Level -eq 'Parent' -and $ExpectedInclude -eq '') {
        try {
            #Write-Information $Domain
            $MXRecord = Read-MXRecord -Domain $Domain
            $SpfResults.MailProvider = $MXRecord.MailProvider
            if ($MXRecord.ExpectedInclude -ne '') {
                $ExpectedInclude = $MXRecord.ExpectedInclude
            }

            if ($MXRecord.MailProvider.Name -eq 'Null') {
                if ($Record -eq 'v=spf1 -all') {
                    $ValidationPasses.Add('This SPF record is valid for a Null MX configuration') | Out-Null
                }
                else {
                    $ValidationFails.Add('This SPF record is not valid for a Null MX configuration. Expected record: "v=spf1 -all"') | Out-Null
                }
            }

            if ($TypeLookups.RecordType -contains 'mx') {
                $Recommendations.Add([pscustomobject]@{
                        Message = "Remove the 'mx' modifier from your record. Check the mail provider documentation for the correct SPF include.";
                        Match   = '\s*([+-~?]?mx)\s+'
                        Replace = ' '
                    }) | Out-Null
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
                $ValidationPasses.Add('The expected mail provider IP address ranges were found.') | Out-Null
            }
            else {
                $ValidationFails.Add('The expected mail provider entry was not found in the record.') | Out-Null
                $Recommendations.Add([pscustomobject]@{
                        Message = ("Add 'include:{0} to your record." -f $ExpectedInclude)
                        Match   = '^v=spf1 (.+?)([-~?+]all)?$'
                        Replace = "v=spf1 include:$ExpectedInclude `$1 `$2"
                    }) | Out-Null
            }
        }
        else {
            $ValidationPasses.Add('The expected mail provider entry is part of the record.') | Out-Null
        }
    }

    # Count total lookups
    $LookupCount = $LookupCount + ($RecordList | Measure-Object -Property LookupCount -Sum).Sum

    if ($Domain -ne 'Not Specified') {
        # Check legacy SPF type
        $LegacySpfType = Resolve-DnsHttpsQuery -Domain $Domain -RecordType 'SPF' -ErrorAction Stop
        if ($null -ne $LegacySpfType -and $LegacySpfType -eq 0) {
            $ValidationWarns.Add("The record type 'SPF' was detected, this is legacy and should not be used. It is recommeded to delete this record (RFC 7208 Section 14.1).") | Out-Null
        }
    }
    if ($Level -eq 'Parent' -and $RecordCount -gt 0) {
        # Check for the correct all mechanism
        if ($AllMechanism -eq '' -and $Record -ne '') { 
            $ValidationFails.Add("The 'all' mechanism is missing from SPF record, the default is a neutral qualifier (?all).") | Out-Null
            $AllMechanism = '?all' 
        }

        if ($AllMechanism -eq '-all') {
            $ValidationPasses.Add('The SPF record ends with a hard fail qualifier (-all). This is best practice and will instruct recipients to discard unauthorized senders.') | Out-Null
        }
        elseif ($Record -ne '') {
            $ValidationFails.Add('The SPF record should end in -all to prevent spamming.') | Out-Null 
            $Recommendations.Add([PSCustomObject]@{
                    Message = "Replace '{0}' with '-all' to make a SPF failure result in a hard fail." -f $AllMechanism
                    Match   = [regex]::escape($AllMechanism)
                    Replace = '-all'
                }) | Out-Null
        }

        # SPF lookup count
        if ($LookupCount -ge 9) {
            $SpecificLookupsFound = $false
            foreach ($SpfRecord in $RecordList) {
                if ($SpfRecord.LookupCount -ge 5) {
                    $SpecificLookupsFound = $true
                    $IncludeLookupCount = $SpfRecord.LookupCount + 1
                    $Match = ('[+-~?]?include:{0}' -f $SpfRecord.Domain)
                    $Recommendations.Add([PSCustomObject]@{
                            Message = ("Remove the include modifier for domain '{0}', this adds {1} lookups towards the max of 10. Alternatively, reduce the number of lookups inside this record if you are able to." -f $SpfRecord.Domain, $IncludeLookupCount)
                            Match   = $Match
                            Replace = ''
                        }) | Out-Null
                } 
            }
            if (!($SpecificLookupsFound)) {
                $Recommendations.Add([PSCustomObject]@{
                        Message = 'Review include modifiers to ensure that your lookup count stays below 10.'
                        Match   = ''
                    }) | Out-Null
            }
        }

        if ($LookupCount -gt 10) { 
            $ValidationFails.Add("Lookup count: $LookupCount/10. The SPF evaluation will fail with a permanent error (RFC 7208 Section 4.6.4).") | Out-Null 
            $Status = 'permerror'
        }
        elseif ($LookupCount -ge 9 -and $LookupCount -le 10) {
            $ValidationWarns.Add("Lookup count: $LookupCount/10. Excessive lookups can cause the SPF evaluation to fail (RFC 7208 Section 4.6.4).") | Out-Null            
        }
        else {
            $ValidationPasses.Add("Lookup count: $LookupCount/10.") | Out-Null
        }

        # Report pass if no PermErrors are found
        if ($Status -ne 'permerror') {
            $ValidationPasses.Add('No permanent errors detected in the SPF record.') | Out-Null
        }

        # Report pass if no errors are found
        if (($ValidationFails | Measure-Object | Select-Object -ExpandProperty Count) -eq 0) {
            $ValidationPasses.Add('All validation checks passed.') | Out-Null
        }
    }

    # Check recommendations for replacement regexes
    if (($Recommendations | Measure-Object).Count -gt 0) {
        $RecommendedRecord = $Record
        foreach ($Rec in $Recommendations) {
            if ($Rec.Match -ne '') {
                # Replace item in record with recommended
                $RecommendedRecord = $RecommendedRecord -replace $Rec.Match, $Rec.Replace
            }
        }
        # Cleanup extra spaces
        $RecommendedRecord = $RecommendedRecord -replace '\s+', ' '
    }

    # Set SPF result object
    $SpfResults.Record = $Record
    $SpfResults.RecordCount = $RecordCount
    $SpfResults.LookupCount = $LookupCount
    $SpfResults.AllMechanism = $AllMechanism
    $SpfResults.ValidationPasses = @($ValidationPasses)
    $SpfResults.ValidationWarns = @($ValidationWarns)
    $SpfResults.ValidationFails = @($ValidationFails)
    $SpfResults.RecordList = @($RecordList)
    $SpfResults.Recommendations = @($Recommendations)
    $SpfResults.RecommendedRecord = $RecommendedRecord
    $SpfResults.TypeLookups = @($TypeLookups)
    $SpfResults.IPAddresses = @($IPAddresses)
    $SpfResults.Status = $Status    

    
    Write-Verbose "-----END SPF RECORD ($Level)-----"
    
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
    ValidationPasses : {Aggregate reports are being sent}
    ValidationWarns  : {Policy is not being enforced, Subdomain policy is only partially enforced with quarantine, Failure report option 0 will only generate a report on both SPF and DKIM misalignment. It is recommended to set this value to 1}
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
        ReportingEmails  = [System.Collections.Generic.List[string]]::new()
        ForensicEmails   = [System.Collections.Generic.List[string]]::new()
        FailureReport    = ''
        ValidationPasses = [System.Collections.Generic.List[string]]::new()
        ValidationWarns  = [System.Collections.Generic.List[string]]::new()
        ValidationFails  = [System.Collections.Generic.List[string]]::new()
    }

    # Validation lists
    $ValidationPasses = [System.Collections.Generic.List[string]]::new()
    $ValidationWarns = [System.Collections.Generic.List[string]]::new()
    $ValidationFails = [System.Collections.Generic.List[string]]::new()

    # Email report domains
    $ReportDomains = [System.Collections.Generic.List[string]]::new()

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

    $Query = Resolve-DnsHttpsQuery @DnsQuery -ErrorAction Stop

    $RecordCount = 0
    $Query.Answer | Where-Object { $_.data -match '^v=DMARC1' } | ForEach-Object {
        $DmarcRecord = $_.data
        $DmarcAnalysis.Record = $DmarcRecord
        $RecordCount++  
    }
    if ($Query.Status -eq 2 -and $Query.AD -eq $false) {
        $ValidationFails.Add('DNSSEC validation failed.') | Out-Null
    }
    elseif ($Query.Status -ne 0 -or $RecordCount -eq 0) {
        $ValidationFails.Add('This domain does not have a DMARC record.') | Out-Null
    }
    elseif (($Query.Answer | Measure-Object).Count -eq 1 -and $RecordCount -eq 0) {
        $ValidationFails.Add("The record must begin with 'v=DMARC1'.") | Out-Null 
    }
    elseif ($RecordCount -gt 1) {
        $ValidationFails.Add('This domain has multiple records. The policy evaluation will fail.') | Out-Null
    }

    # Split DMARC record into name/value pairs
    $TagList = [System.Collections.Generic.List[object]]::new()
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
                    if ($MailTo -notmatch '^mailto:') { $ValidationFails.Add("Aggregate report email addresses must begin with 'mailto:', multiple addresses must be separated by commas.") | Out-Null }
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
                    $ValidationPasses.Add('Aggregate reports are being sent.') | Out-Null
                }
                else {
                    $ValidationWarns.Add('Aggregate reports are not being sent.') | Out-Null
                }
            }
            'ruf' {
                # Forensic reporting emails
                foreach ($MailTo in ($Tag.Value -split ', ')) {
                    if ($MailTo -notmatch '^mailto:') { $ValidationFails.Add("Forensic report email must begin with 'mailto:', multiple addresses must be separated by commas - found $($Tag.Value)") | Out-Null }
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
                $ReportDmarcQuery = Resolve-DnsHttpsQuery @DnsQuery -ErrorAction Stop
                $ReportDmarcRecord = $ReportDmarcQuery.Answer.data
                if ($null -eq $ReportDmarcQuery -or $ReportDmarcQuery.Status -ne 0) {
                    $ValidationWarns.Add("Report DMARC policy for $Domain is missing from $ReportDomain, reports will not be delivered. Expected record: '$Domain._report._dmarc.$ReportDomain' - Expected value: 'v=DMARC1;'") | Out-Null
                    $ReportDomainsPass = $false
                }
                elseif ($ReportDmarcRecord -notmatch '^v=DMARC1') {
                    $ValidationWarns.Add("Report DMARC policy for $Domain is missing from $ReportDomain, reports will not be delivered. Expected record: '$Domain._report._dmarc.$ReportDomain' - Expected value: 'v=DMARC1;'.") | Out-Null
                    $ReportDomainsPass = $false
                }
            }

            if ($ReportDomainsPass) {
                $ValidationPasses.Add('All external reporting domains allow this domain to send DMARC reports.') | Out-Null
            }

        }
        # Check for missing record tags and set defaults
        if ($DmarcAnalysis.Policy -eq '') { $ValidationFails.Add('The policy tag (p=) is missing from this record. Set this to none, quarantine or reject.') | Out-Null }
        if ($DmarcAnalysis.SubdomainPolicy -eq '') { $DmarcAnalysis.SubdomainPolicy = $DmarcAnalysis.Policy }

        # Check policy for errors and best practice
        if ($PolicyValues -notcontains $DmarcAnalysis.Policy) { $ValidationFails.Add("The policy must be one of the following: none, quarantine or reject. Found $($Tag.Value)") | Out-Null }
        if ($DmarcAnalysis.Policy -eq 'reject') { $ValidationPasses.Add('The domain policy is set to reject, this is best practice.') | Out-Null }
        if ($DmarcAnalysis.Policy -eq 'quarantine') { $ValidationWarns.Add('The domain policy is only partially enforced with quarantine. Set this to reject to be fully compliant.') | Out-Null }
        if ($DmarcAnalysis.Policy -eq 'none') { $ValidationFails.Add('The domain policy is not being enforced.') | Out-Null }

        # Check subdomain policy
        if ($PolicyValues -notcontains $DmarcAnalysis.SubdomainPolicy) { $ValidationFails.Add("The subdomain policy must be one of the following: none, quarantine or reject. Found $($DmarcAnalysis.SubdomainPolicy)") | Out-Null }
        if ($DmarcAnalysis.SubdomainPolicy -eq 'reject') { $ValidationPasses.Add('The subdomain policy is set to reject, this is best practice.') | Out-Null }
        if ($DmarcAnalysis.SubdomainPolicy -eq 'quarantine') { $ValidationWarns.Add('The subdomain policy is only partially enforced with quarantine. Set this to reject to be fully compliant.') | Out-Null }
        if ($DmarcAnalysis.SubdomainPolicy -eq 'none') { $ValidationFails.Add('The subdomain policy is not being enforced.') | Out-Null }

        # Check percentage - validate range and ensure 100%
        if ($DmarcAnalysis.Percent -lt 100 -and $DmarcAnalysis.Percent -ge 0) { $ValidationWarns.Add('Not all emails will be processed by the DMARC policy.') | Out-Null }
        if ($DmarcAnalysis.Percent -gt 100 -or $DmarcAnalysis.Percent -lt 0) { $ValidationFails.Add('The percentage tag (pct=) must be between 0 and 100.') | Out-Null }

        # Check report format
        if ($ReportFormatValues -notcontains $DmarcAnalysis.ReportFormat) { $ValidationFails.Add("The report format '$($DmarcAnalysis.ReportFormat)' is not supported.") | Out-Null }
 
        # Check forensic reports and failure options
        $ForensicCount = ($DmarcAnalysis.ForensicEmails | Measure-Object | Select-Object -ExpandProperty Count)
        if ($ForensicCount -eq 0 -and $DmarcAnalysis.FailureReport -ne '') { $ValidationWarns.Add('Forensic email reports recipients are not defined and failure report options are set. No reports will be sent. This is not an issue unless you are expecting forensic reports.') | Out-Null }
        if ($DmarcAnalysis.FailureReport -eq '' -and $null -ne $DmarcRecord) { $DmarcAnalysis.FailureReport = '0' }
        if ($ForensicCount -gt 0) {
            $ReportOptions = $DmarcAnalysis.FailureReport -split ':'
            foreach ($ReportOption in $ReportOptions) {
                if ($FailureReportValues -notcontains $ReportOption) { $ValidationFails.Add("Failure report option '$ReportOption' is not a valid choice.") | Out-Null }
                if ($ReportOption -eq '1') { $ValidationPasses.Add('Failure report option 1 generates forensic reports on SPF or DKIM misalignment.') | Out-Null }
                if ($ReportOption -eq '0' -and $ReportOptions -notcontains '1') { $ValidationWarns.Add('Failure report option 0 will only generate a forensic report on both SPF and DKIM misalignment. It is recommended to set this value to 1.') | Out-Null }
                if ($ReportOption -eq 'd' -and $ReportOptions -notcontains '1') { $ValidationWarns.Add('Failure report option d will only generate a forensic report on failed DKIM evaluation. It is recommended to set this value to 1.') | Out-Null }
                if ($ReportOption -eq 's' -and $ReportOptions -notcontains '1') { $ValidationWarns.Add('Failure report option s will only generate a forensic report on failed SPF evaluation. It is recommended to set this value to 1.') | Out-Null }
            }
        }
    }

    # Add the validation lists
    $DmarcAnalysis.ValidationPasses = @($ValidationPasses)
    $DmarcAnalysis.ValidationWarns = @($ValidationWarns)
    $DmarcAnalysis.ValidationFails = @($ValidationFails)

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
        Selectors        = $Selectors
        MailProvider     = ''
        Records          = [System.Collections.Generic.List[object]]::new()
        ValidationPasses = [System.Collections.Generic.List[string]]::new()
        ValidationWarns  = [System.Collections.Generic.List[string]]::new()
        ValidationFails  = [System.Collections.Generic.List[string]]::new()
    }

    $ValidationPasses = [System.Collections.Generic.List[string]]::new()
    $ValidationWarns = [System.Collections.Generic.List[string]]::new()
    $ValidationFails = [System.Collections.Generic.List[string]]::new()

    # MX lookup, check for defined selectors
    try {
        $MXRecord = Read-MXRecord -Domain $Domain
        foreach ($Selector in $MXRecord.Selectors) {
            try {
                $Selectors.Add($Selector) | Out-Null
            }
            catch {}
        }
        $DkimAnalysis.MailProvider = $MXRecord.MailProvider
        if ($MXRecord.MailProvider.PSObject.Properties.Name -contains 'MinimumSelectorPass') {
            $MinimumSelectorPass = $MXRecord.MailProvider.MinimumSelectorPass
        }
        $DkimAnalysis.Selectors = $Selectors
    }
    catch {}

    # Get unique selectors
    $Selectors = $Selectors | Sort-Object -Unique
    
    if (($Selectors | Measure-Object | Select-Object -ExpandProperty Count) -gt 0) {
        foreach ($Selector in $Selectors) {
            if (![string]::IsNullOrEmpty($Selector)) {
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
                    UnrecognizedTags = [System.Collections.Generic.List[object]]::new()
                }

                $DnsQuery = @{
                    RecordType = 'TXT'
                    Domain     = "$Selector._domainkey.$Domain"
                }

                try {
                    $QueryResults = Resolve-DnsHttpsQuery @DnsQuery -ErrorAction Stop
                }
                catch { 
                    $Message = "{0}`r`n{1}" -f $_.Exception.Message, ($DnsQuery | ConvertTo-Json)
                    throw $Message
                }
                if ([string]::IsNullOrEmpty($Selector)) { continue }
            
                if ($QueryResults.Status -eq 2 -and $QueryResults.AD -eq $false) {
                    $ValidationFails.Add('DNSSEC validation failed.') | Out-Null
                }
                if ($QueryResults -eq '' -or $QueryResults.Status -ne 0) {
                    if ($QueryResults.Status -eq 3) {
                        if ($MinimumSelectorPass -eq 0) {
                            $ValidationFails.Add("$Selector - The selector record does not exist for this domain.") | Out-Null
                        }
                    }
                    else {
                        $ValidationFails.Add("$Selector - DKIM record is missing, check the selector and try again") | Out-Null
                    }
                    $Record = ''
                }
                else {
                    $QueryData = ($QueryResults.Answer).data | Where-Object { $_ -match '(v=|k=|t=|p=)' }
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
                $TagList = [System.Collections.Generic.List[object]]::new()
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
                    if ($x -eq 0 -and $Tag.Value -ne 'DKIM1') { $ValidationFails.Add("$Selector - The record must being with 'v=DKIM1'.") | Out-Null }
            
                    switch ($Tag.Name) {
                        'v' {
                            # REQUIRED: Version
                            if ($x -ne 0) { $ValidationFails.Add("$Selector - The record must being with 'v=DKIM1'.") | Out-Null }
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
                                    $ValidationPasses.Add("$Selector - DKIM configuration is valid for a Null MX record configuration.") | Out-Null
                                }
                                else {
                                    $ValidationFails.Add("$Selector - There is no public key specified for this DKIM record or the key is revoked.") | Out-Null 
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
                        $ValidationWarns.Add("$Selector - $UnrecognizedTagCount urecognized tag(s) were detected in the DKIM record. This can cause issues with some mailbox providers. Tags: $TagString")
                    }
                    if ($DkimRecord.Flags -eq 'y') {
                        $ValidationWarns.Add("$Selector - The flag 't=y' indicates that this domain is testing mode currently. If DKIM is fully deployed, this flag should be changed to t=s unless subdomaining is required.") | Out-Null
                    }

                    if ($DkimRecord.PublicKeyInfo.SignatureAlgorithm -ne $DkimRecord.KeyType -and $MXRecord.MailProvider.Name -ne 'Null') {
                        $ValidationWarns.Add("$Selector - Key signature algorithm $($DkimRecord.PublicKeyInfo.SignatureAlgorithm) does not match $($DkimRecord.KeyType)") | Out-Null
                    }

                    if ($DkimRecord.PublicKeyInfo.KeySize -lt 1024 -and $MXRecord.MailProvider.Name -ne 'Null') {
                        $ValidationFails.Add("$Selector - Key size is less than 1024 bit, found $($DkimRecord.PublicKeyInfo.KeySize).") | Out-Null
                    }
                    else {
                        if ($MXRecord.MailProvider.Name -ne 'Null') {
                            $ValidationPasses.Add("$Selector - DKIM key validation succeeded.") | Out-Null
                        }
                        $SelectorPasses++
                    }

                    if (($ValidationFails | Measure-Object | Select-Object -ExpandProperty Count) -eq 0) {
                        $ValidationPasses.Add("$Selector - No errors detected with DKIM record.") | Out-Null
                    }
                }    
            ($DkimAnalysis.Records).Add($DkimRecord) | Out-Null
            }
        }
    }
    if (($DkimAnalysis.Records | Measure-Object | Select-Object -ExpandProperty Count) -eq 0 -and [string]::IsNullOrEmpty($DkimAnalysis.Selectors)) {
        $ValidationWarns.Add('No DKIM selectors provided, set them in the domain options.') | Out-Null
    }

    if ($MinimumSelectorPass -gt 0 -and $SelectorPasses -eq 0) {
        $ValidationFails.Add(('{0} DKIM record(s) found. The minimum number of valid records ({1}) was not met.' -f $SelectorPasses, $MinimumSelectorPass)) | Out-Null
    }
    elseif ($MinimumSelectorPass -gt 0 -and $SelectorPasses -ge $MinimumSelectorPass) {
        $ValidationPasses.Add(('Minimum number of valid DKIM records were met {0}/{1}.' -f $SelectorPasses, $MinimumSelectorPass))
    }

    # Collect validation results
    $DkimAnalysis.ValidationPasses = @($ValidationPasses)
    $DkimAnalysis.ValidationWarns = @($ValidationWarns)
    $DkimAnalysis.ValidationFails = @($ValidationFails)

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

    # Top level referring servers, IANA, ARIN and AUDA
    $TopLevelReferrers = @('whois.iana.org', 'whois.arin.net', 'whois.auda.org.au')

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
        'Registrar', 'Registrar Name'
    )

    # Whois parser, generic Property: Value format with some multi-line support and comment handlers
    $WhoisRegex = '^(?!(?:%|>>>|-+|#|[*]))[^\S\n]*(?<PropName>.+?):(?:[\r\n]+)?(:?(?!([0-9]|[/]{2}))[^\S\r\n]*(?<PropValue>.+))?$'

    # TCP Client for Whois
    $Client = New-Object System.Net.Sockets.TcpClient($Server, 43)
    try {
        # Open TCP connection and send query
        $Stream = $Client.GetStream()
        $ReferralServers = [System.Collections.Generic.List[string]]::new()
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
                if ($Results.$RegistrarProp -eq 'Registrar') {
                    break  # Means we always favour Registrar if it exists, or keep looking
                }
            }
        }

        # Store raw results and query metadata
        $Results._Raw = $Raw
        $Results._ReferralServers = [System.Collections.Generic.List[string]]::new()
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
                $Results = Read-WhoisRecord -Query $Query -Server $ReferralServer -Port $Port
                if ($Results._Raw -Match '(No match|Not Found|No Data|The queried object does not exist)' -and $TopLevelReferrers -notcontains $Server) { 
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
            if ($Results._Raw -Match '(No match|Not Found|No Data)') {
                $first, $newquery = ($Query -split '\.')
                if (($newquery | Measure-Object).Count -gt 1) {
                    $Query = $newquery -join '.'
                    $Results = Read-WhoisRecord -Query $Query -Server $Server -Port $Port
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
    try {
        if (!('SevenTiny.Bantina.Security.RSACommon' -as [type])) {
            Add-Type -TypeDefinition $source -Language CSharp
        }
    }
    catch {}

    # Return RSA Public Key information
    [SevenTiny.Bantina.Security.RSACommon]::CreateRsaProviderFromPublicKey($EncodedString)
}

function Test-HttpsCertificate {
    <#
    .SYNOPSIS
    Test HTTPS certificate for Domain
    
    .DESCRIPTION
    This function aggregates test results for a domain and subdomains in regards to
    HTTPS certificates
    
    .PARAMETER Domain
    Domain to check
    
    .PARAMETER Subdomains
    List of subdomains
    
    .EXAMPLE
    PS> Test-HttpsCertificate -Domain badssl.com -Subdomains expired, revoked

    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Domain,
        [string[]]$Subdomains = @()
    )
    
    $CertificateTests = [PSCustomObject]@{
        Domain           = $Domain
        UrlsToTest       = [System.Collections.Generic.List[string]]::new()
        Tests            = [System.Collections.Generic.List[object]]::new()
        ValidationPasses = [System.Collections.Generic.List[string]]::new()
        ValidationWarns  = [System.Collections.Generic.List[string]]::new()
        ValidationFails  = [System.Collections.Generic.List[string]]::new()
    }

    $Urls = [System.Collections.Generic.List[string]]::new()
    $Urls.Add(('https://{0}' -f $Domain)) | Out-Null

    if (($Subdomains | Measure-Object).Count -gt 0) {
        foreach ($Subdomain in $Subdomains) {
            $Urls.Add(('https://{0}.{1}' -f $Subdomain, $Domain)) | Out-Null
        }
    }
    
    $CertificateTests.UrlsToTest = $Urls

    $CertificateTests.Tests = foreach ($Url in $Urls) {
        $Test = [PSCustomObject]@{
            Hostname         = ''
            Certificate      = ''
            Chain            = ''
            HttpResponse     = ''
            ValidityDays     = 0
            ValidationPasses = [System.Collections.Generic.List[string]]::new()
            ValidationWarns  = [System.Collections.Generic.List[string]]::new()
            ValidationFails  = [System.Collections.Generic.List[string]]::new()
            Errors           = [System.Collections.Generic.List[string]]::new()
        }      
        try {
            # Parse URL and extract hostname
            $ParsedUrl = [System.Uri]::new($Url)
            $Hostname = $ParsedUrl.Host

            # Valdiations
            $ValidationPasses = [System.Collections.Generic.List[string]]::new()
            $ValidationWarns = [System.Collections.Generic.List[string]]::new()
            $ValidationFails = [System.Collections.Generic.List[string]]::new()

            # Grab certificate data
            $Validation = Get-ServerCertificateValidation -Url $Url
            $Certificate = $Validation.Certificate | Select-Object FriendlyName, IssuerName, NotBefore, NotAfter, SerialNumber, SignatureAlgorithm, SubjectName, Thumbprint, Issuer, Subject, DnsNameList
            $HttpResponse = $Validation.HttpResponse
            $Chain = $Validation.Chain

            $CurrentDate = Get-Date
            $TimeSpan = New-TimeSpan -Start $CurrentDate -End $Certificate.NotAfter

            # Check to see if certificate is contained in the DNS name list
            if ($Certificate.DnsNameList -contains $Hostname -or $Certificate.DnsNameList -eq "*.$Domain") {
                $ValidationPasses.Add(('{0} - Certificate DNS name list contains hostname.' -f $Hostname)) | Out-Null
            }
            else {
                $ValidationFails.Add(('{0} - Certificate DNS name list does not contain hostname' -f $Hostname)) | Out-Null
            }

            # Check certificate validity
            if ($Certificate.NotBefore -ge $CurrentDate) {
                # NotBefore is in the future
                $ValidationFails.Add(('{0} - Certificate is not yet valid.' -f $Hostname)) | Out-Null
            }
            elseif ($Certificate.NotAfter -le $CurrentDate) {
                # NotAfter is in the past
                $ValidationFails.Add(('{0} - Certificate expired {1} day(s) ago.' -f $Hostname, [Math]::Abs($TimeSpan.Days))) | Out-Null
            }
            elseif ($Certificate.NotAfter -ge $CurrentDate -and $TimeSpan.Days -lt 30) {
                # NotAfter is under 30 days away
                $ValidationWarns.Add(('{0} - Certificate will expire in {1} day(s).' -f $Hostname, $TimeSpan.Days)) | Out-Null
            }
            else {
                # Certificate is valid and not expired
                $ValidationPasses.Add(('{0} - Certificate is valid for the next {1} days.' -f $Hostname, $TimeSpan.Days)) | Out-Null
            }

            # Certificate chain errors
            if (($Chain.ChainStatus | Measure-Object).Count -gt 0) {
                foreach ($Status in $Chain.ChainStatus) {
                    $ValidationFails.Add(('{0} - {1}' -f $Hostname, $Status.StatusInformation)) | Out-Null
                }
            }

            # Website status errorr
            if ([int]$HttpResponse.StatusCode -ge 400) {
                $ValidationFails.Add(('{0} - Website responded with: {1}' -f $Hostname, $HttpResponse.ReasonPhrase))
            } 

            # Set values and return Test object
            $Test.Hostname = $Hostname
            $Test.Certificate = $Certificate
            $Test.Chain = $Chain
            $Test.HttpResponse = $HttpResponse
            $Test.ValidityDays = $TimeSpan.Days

            $Test.ValidationPasses = @($ValidationPasses)
            $Test.ValidationWarns = @($ValidationWarns)
            $Test.ValidationFails = @($ValidationFails)

            # Return test
            $Test
        }
        catch {}
    }

    # Aggregate validation results
    foreach ($Test in $CertificateTests.Tests) {
        $ValidationPassCount = ($Test.ValidationPasses | Measure-Object).Count
        $ValidationWarnCount = ($Test.ValidationWarns | Measure-Object).Count
        $ValidationFailCount = ($Test.ValidationFails | Measure-Object).Count

        if ($ValidationFailCount -gt 0) {
            $CertificateTests.ValidationFails.Add(('{0} - Failure on {1} check(s)' -f $Test.Hostname, $ValidationFailCount)) | Out-Null
        }
        
        if ($ValidationWarnCount -gt 0) {
            $CertificateTests.ValidationWarns.Add(('{0} - Warning on {1} check(s)' -f $Test.Hostname, $ValidationWarnCount)) | Out-Null
        }

        if ($ValidationPassCount -gt 0) {
            $CertificateTests.ValidationPasses.Add(('{0} - Pass on {1} check(s)' -f $Test.Hostname, $ValidationPassCount)) | Out-Null
        }
    }
    
    # Return tests
    $CertificateTests
}


function Get-ServerCertificateValidation {
    <#
    .SYNOPSIS
    Get HTTPS certificate and chain information for Url
    
    .DESCRIPTION
    Obtains certificate data from .Net HttpClient and builds certificate chain to
    verify validity and revocation status
    
    .PARAMETER Url
    Url to check
    
    .PARAMETER FollowRedirect
    Follow HTTP redirects
    
    .EXAMPLE
    PS> Get-ServerCertificateValidation -Url https://expired.badssl.com
    
    #>
    Param(
        [Parameter(Mandatory = $true)]
        $Url,
        [switch]$FollowRedirect
    )
    $source = @'
using System;
using System.Net.Http;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
using System.Threading.Tasks;

namespace CyberDrain.CIPP {

    public class CertValidation {
        public HttpResponseMessage HttpResponse;
        public X509Certificate2 Certificate;
        public X509Chain Chain;
        public SslPolicyErrors SslErrors;
    }

    public static class CertificateCheck {
        public static CertValidation GetServerCertificate(string url, bool allowredirect=false)
        {
            CertValidation certvalidation = new CertValidation();
            var httpClientHandler = new HttpClientHandler
            {
                AllowAutoRedirect = allowredirect,
                ServerCertificateCustomValidationCallback = (requestMessage, cert, chain, sslErrors) =>
                {
                    X509Chain ch = new X509Chain();
                    ch.ChainPolicy.RevocationFlag = X509RevocationFlag.EntireChain;
                    ch.ChainPolicy.RevocationMode = X509RevocationMode.Online;
                    ch.ChainPolicy.VerificationFlags = X509VerificationFlags.AllFlags;
                    //ch.ChainPolicy.DisableCertificateDownloads = true;
                    certvalidation.Certificate = new X509Certificate2(cert.GetRawCertData());
                    ch.Build(cert);
                    certvalidation.Chain = ch;
                    certvalidation.SslErrors = sslErrors;
                    return true;
                }
            };

            var httpClient = new HttpClient(httpClientHandler);
            HttpResponseMessage HttpResponse = Task.Run(async() => await httpClient.SendAsync(new HttpRequestMessage(HttpMethod.Get, url))).Result;
            certvalidation.HttpResponse = HttpResponse;
            return certvalidation;
        }
    }
}
'@
    try { 
        if (!('CyberDrain.CIPP.CertificateCheck' -as [type])) {
            Add-Type -TypeDefinition $source -Language CSharp
        }
    }
    catch {}

    [CyberDrain.CIPP.CertificateCheck]::GetServerCertificate($Url, $FollowRedirect)
}

function Test-MtaSts {
    <#
    .SYNOPSIS
    Perform MTA-STS and TLSRPT checks
    
    .DESCRIPTION
    Retrieve MTA-STS record, policy and TLSRPT record
    
    .PARAMETER Domain
    Domain to process
    
    .EXAMPLE
    PS> Test-MtaSts -Domain gmail.com

    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    # MTA-STS test object
    $MtaSts = [PSCustomObject]@{
        Domain           = $Domain
        StsRecord        = (Read-MtaStsRecord -Domain $Domain)
        StsPolicy        = (Read-MtaStsPolicy -Domain $Domain)
        TlsRptRecord     = (Read-TlsRptRecord -Domain $Domain)
        ValidationPasses = [System.Collections.Generic.List[string]]::new()
        ValidationWarns  = [System.Collections.Generic.List[string]]::new()
        ValidationFails  = [System.Collections.Generic.List[string]]::new()
    }

    # Validation lists
    $ValidationPasses = [System.Collections.Generic.List[string]]::new()
    $ValidationWarns = [System.Collections.Generic.List[string]]::new()
    $ValidationFails = [System.Collections.Generic.List[string]]::new()

    # Check results for each test
    if ($MtaSts.StsRecord.IsValid) { $ValidationPasses.Add('MTA-STS Record is valid') | Out-Null }
    else { $ValidationFails.Add('MTA-STS Record is not valid') | Out-Null }
    if ($MtaSts.StsRecord.HasWarnings) { $ValidationWarns.Add('MTA-STS Record has warnings') | Out-Null }

    if ($MtaSts.StsPolicy.IsValid) { $ValidationPasses.Add('MTA-STS Policy is valid') | Out-Null }
    else { $ValidationFails.Add('MTA-STS Policy is not valid') | Out-Null }
    if ($MtaSts.StsPolicy.HasWarnings) { $ValidationWarns.Add('MTA-STS Policy has warnings') | Out-Null }

    if ($MtaSts.TlsRptRecord.IsValid) { $ValidationPasses.Add('TLSRPT Record is valid') | Out-Null }
    else { $ValidationFails.Add('TLSRPT Record is not valid') | Out-Null }
    if ($MtaSts.TlsRptRecord.HasWarnings) { $ValidationWarns.Add('TLSRPT Record has warnings') | Out-Null }

    # Aggregate validation results
    $MtaSts.ValidationPasses = $ValidationPasses
    $MtaSts.ValidationWarns = $ValidationWarns
    $MtaSts.ValidationFails = $ValidationFails

    $MtaSts
}

function Read-MtaStsRecord {
    <#
    .SYNOPSIS
    Resolve and validate MTA-STS record
    
    .DESCRIPTION
    Query domain for DMARC policy (_mta-sts.domain.com) and parse results. Record is checked for issues.
    
    .PARAMETER Domain
    Domain to process MTA-STS record
    
    .EXAMPLE
    PS> Read-MtaStsRecord -Domain gmail.com

    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    # Initialize object
    $StsAnalysis = [PSCustomObject]@{
        Domain           = $Domain
        Record           = ''
        Version          = ''
        Id               = ''
        IsValid          = $false
        HasWarnings      = $false
        ValidationPasses = [System.Collections.Generic.List[string]]::new()
        ValidationWarns  = [System.Collections.Generic.List[string]]::new()
        ValidationFails  = [System.Collections.Generic.List[string]]::new()
    }

    # Validation lists
    $ValidationPasses = [System.Collections.Generic.List[string]]::new()
    $ValidationWarns = [System.Collections.Generic.List[string]]::new()
    $ValidationFails = [System.Collections.Generic.List[string]]::new()

    # Validation ranges

    $RecordCount = 0

    $DnsQuery = @{
        RecordType = 'TXT'
        Domain     = "_mta-sts.$Domain"
    }
    
    # Resolve DMARC record

    $Query = Resolve-DnsHttpsQuery @DnsQuery -ErrorAction Stop

    $RecordCount = 0
    $Query.Answer | Where-Object { $_.data -match '^v=STSv1' } | ForEach-Object {
        $StsRecord = $_.data
        $StsAnalysis.Record = $StsRecord
        $RecordCount++  
    }
    if ($Query.Status -eq 2 -and $Query.AD -eq $false) {
        $ValidationFails.Add('DNSSEC validation failed.') | Out-Null
    }
    elseif ($Query.Status -ne 0 -or $RecordCount -eq 0) {
        if ($Query.Status -eq 3) {
            $ValidationFails.Add('Record does not exist (NXDOMAIN)') | Out-Null
        }
        else {
            $ValidationFails.Add("$Domain does not have an MTA-STS record") | Out-Null
        }
    }
    elseif ($RecordCount -gt 1) {
        $ValidationFails.Add("$Domain has multiple MTA-STS records") | Out-Null
    }

    # Split DMARC record into name/value pairs
    $TagList = [System.Collections.Generic.List[object]]::new()
    Foreach ($Element in ($StsRecord -split ';').trim()) {
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
                if ($x -ne 0) { $ValidationFails.Add('v=STSv1 must be at the beginning of the record') | Out-Null }
                if ($Tag.Value -ne 'STSv1') { $ValidationFails.Add("Version must be STSv1 - found $($Tag.Value)") | Out-Null }
                $StsAnalysis.Version = $Tag.Value
            }
            'id' {
                # REQUIRED: Id
                $StsAnalysis.Id = $Tag.Value
            }

        }
        $x++
    }

    if ($RecordCount -gt 0) {
        # Check for missing record tags and set defaults
        if ($StsAnalysis.Id -eq '') { $ValidationFails.Add('Id record is missing') | Out-Null }
        elseif ($StsAnalysis.Id -notmatch '^[A-Za-z0-9]+$') {
            $ValidationFails.Add('STS Record ID must be alphanumeric') | Out-Null 
        }
            
        if ($RecordCount -gt 1) {
            $ValidationWarns.Add('Multiple MTA-STS records detected, this may cause unexpected behavior.') | Out-Null
            $StsAnalysis.HasWarnings = $true
        }
        
        $ValidationWarnCount = ($Test.ValidationWarns | Measure-Object).Count
        $ValidationFailCount = ($Test.ValidationFails | Measure-Object).Count
        if ($ValidationFailCount -eq 0 -and $ValidationWarnCount -eq 0) {
            $ValidationPasses.Add('MTA-STS record is valid') | Out-Null
            $StsAnalysis.IsValid = $true
        }
    }

    # Add the validation lists
    $StsAnalysis.ValidationPasses = @($ValidationPasses)
    $StsAnalysis.ValidationWarns = @($ValidationWarns)
    $StsAnalysis.ValidationFails = @($ValidationFails)

    # Return MTA-STS analysis
    $StsAnalysis
}

function Read-MtaStsPolicy {
    <#
    .SYNOPSIS
    Resolve and validate MTA-STS policy
    
    .DESCRIPTION
    Retrieve mta-sts.txt from .well-known directory on domain
    
    .PARAMETER Domain
    Domain to process MTA-STS policy 
    
    .EXAMPLE
    PS> Read-MtaStsPolicy -Domain gmail.com
    #>   
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    $StsPolicyAnalysis = [PSCustomObject]@{
        Domain           = $Domain
        Version          = ''
        Mode             = ''
        Mx               = [System.Collections.Generic.List[string]]::new()
        MaxAge           = ''
        IsValid          = $false
        HasWarnings      = $false
        ValidationPasses = [System.Collections.Generic.List[string]]::new()
        ValidationWarns  = [System.Collections.Generic.List[string]]::new()
        ValidationFails  = [System.Collections.Generic.List[string]]::new()
    }

    $ValidationPasses = [System.Collections.Generic.List[string]]::new()
    $ValidationWarns = [System.Collections.Generic.List[string]]::new()
    $ValidationFails = [System.Collections.Generic.List[string]]::new()

    # Valid policy modes
    $StsPolicyModes = @('testing', 'enforce')

    # Request policy file from domain, only accept text/plain results
    $RequestParams = @{
        Uri     = ('https://mta-sts.{0}/.well-known/mta-sts.txt' -f $Domain)
        Headers = @{
            Accept = 'text/plain'
        }
    }

    $PolicyExists = $false
    try {
        $wr = Invoke-WebRequest @RequestParams -ErrorAction Stop
        $PolicyExists = $true
    }
    catch {
        $ValidationFails.Add(('MTA-STS policy does not exist for {0}' -f $Domain)) | Out-Null
    }

    # Policy file is key value pairs split on new lines
    $StsPolicyEntries = [System.Collections.Generic.List[object]]::new()
    $Entries = $wr.Content -split "`r?`n"
    foreach ($Entry in $Entries) {
        if ($null -ne $Entry) {
            try {
                $Name, $Value = $Entry -split ':'
                $StsPolicyEntries.Add(
                    [PSCustomObject]@{
                        Name  = $Name.trim()
                        Value = $Value.trim()
                    }
                ) | Out-Null
            }
            catch {}
        }
    }

    foreach ($StsPolicyEntry in $StsPolicyEntries) {
        switch ($StsPolicyEntry.Name) {
            'version' {
                # REQUIRED: Version
                $StsPolicyAnalysis.Version = $StsPolicyEntry.Value
            }
            'mode' {
                $StsPolicyAnalysis.Mode = $StsPolicyEntry.Value
            }
            'mx' {
                $StsPolicyAnalysis.Mx.Add($StsPolicyEntry.Value) | Out-Null
            }
            'max_age' {
                $StsPolicyAnalysis.MaxAge = $StsPolicyEntry.Value
            }
        }
    }

    # Check policy for issues
    if ($PolicyExists) {
        if ($StsPolicyAnalysis.Version -ne 'STSv1') { 
            $ValidationFails.Add("Version must be STSv1 - found $($StsPolicyEntry.Value)") | Out-Null 
        }
        if ($StsPolicyAnalysis.Version -eq '') {
            $ValidationFails.Add('Version is missing from policy') | Out-Null
        }
        if ($StsPolicyModes -notcontains $StsPolicyAnalysis.Mode) {
            $ValidationFails.Add(('Policy mode "{0}" is not valid. (Options: {1})' -f $StsPolicyAnalysis.Mode, $StsPolicyModes -join ', '))
        }
        if ($StsPolicyAnalysis.Mode -eq 'Testing') { 
            $ValidationWarns.Add('MTA-STS policy is in testing mode, no action will be taken') | Out-Null 
            $StsPolicyAnalysis.HasWarnings = $true
        }

        $ValidationFailCount = ($ValidationFails | Measure-Object).Count
        if ($ValidationFailCount -eq 0) {
            $ValidationPasses.Add('MTA-STS policy is valid')
            $StsPolicyAnalysis.IsValid = $true
        }
    }

    # Aggregate validation results
    $StsPolicyAnalysis.ValidationPasses = @($ValidationPasses)
    $StsPolicyAnalysis.ValidationWarns = @($ValidationWarns)
    $StsPolicyAnalysis.ValidationFails = @($ValidationFails)

    $StsPolicyAnalysis
}

function Read-TlsRptRecord {
    <#
    .SYNOPSIS
    Resolve and validate TLSRPT record
    
    .DESCRIPTION
    Query domain for TLSRPT record (_smtp._tls.domain.com) and parse results. Record is checked for issues.
    
    .PARAMETER Domain
    Domain to process TLSRPT record
    
    .EXAMPLE
    PS> Read-TlsRptRecord -Domain gmail.com

    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    # Initialize object
    $TlsRptAnalysis = [PSCustomObject]@{
        Domain           = $Domain
        Record           = ''
        Version          = ''
        RuaEntries       = [System.Collections.Generic.List[string]]::new()
        IsValid          = $false
        HasWarnings      = $false
        ValidationPasses = [System.Collections.Generic.List[string]]::new()
        ValidationWarns  = [System.Collections.Generic.List[string]]::new()
        ValidationFails  = [System.Collections.Generic.List[string]]::new()
    }

    $ValidRuaProtocols = @(
        '^(?<Rua>https:.+)$'
        '^mailto:(?<Rua>.+)$'
    )

    # Validation lists
    $ValidationPasses = [System.Collections.Generic.List[string]]::new()
    $ValidationWarns = [System.Collections.Generic.List[string]]::new()
    $ValidationFails = [System.Collections.Generic.List[string]]::new()

    # Validation ranges

    $RecordCount = 0

    $DnsQuery = @{
        RecordType = 'TXT'
        Domain     = "_smtp._tls.$Domain"
    }
    
    # Resolve DMARC record

    $Query = Resolve-DnsHttpsQuery @DnsQuery -ErrorAction Stop

    $RecordCount = 0
    $Query.Answer | Where-Object { $_.data -match '^v=TLSRPTv1' } | ForEach-Object {
        $TlsRtpRecord = $_.data
        $TlsRptAnalysis.Record = $TlsRtpRecord
        $RecordCount++  
    }
    if ($Query.Status -eq 2 -and $Query.AD -eq $false) {
        $ValidationFails.Add('DNSSEC validation failed.') | Out-Null
    }
    if ($Query.Status -ne 0 -or $RecordCount -eq 0) {
        if ($Query.Status -eq 3) {
            $ValidationFails.Add('Record does not exist (NXDOMAIN)') | Out-Null
        }
        else {
            $ValidationFails.Add("$Domain does not have an TLSRPT record") | Out-Null
        }
    }
    elseif ($RecordCount -gt 1) {
        $ValidationFails.Add("$Domain has multiple TLSRPT records") | Out-Null
    }

    # Split DMARC record into name/value pairs
    $TagList = [System.Collections.Generic.List[object]]::new()
    Foreach ($Element in ($TlsRtpRecord -split ';').trim()) {
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
                if ($x -ne 0) { $ValidationFails.Add('v=TLSRPTv1 must be at the beginning of the record') | Out-Null }
                if ($Tag.Value -ne 'TLSRPTv1') { $ValidationFails.Add("Version must be TLSRPTv1 - found $($Tag.Value)") | Out-Null }
                $TlsRptAnalysis.Version = $Tag.Value
            }
            'rua' {
                $RuaMatched = $false
                $RuaEntries = $Tag.Value -split ','
                foreach ($RuaEntry in $RuaEntries) {
                    foreach ($Protocol in $ValidRuaProtocols) {
                        if ($RuaEntry -match $Protocol) {
                            $TlsRptAnalysis.RuaEntries.Add($Matches.Rua) | Out-Null
                            $RuaMatched = $true
                        }
                    }
                }
                if ($RuaMatched) {
                    $ValidationPasses.Add('Aggregate reports are being sent') | Out-Null
                }
                else {
                    $ValidationWarns.Add('Aggregate reports are not being sent') | Out-Null
                    $TlsRptAnalysis.HasWarnings = $true
                }
            }
        }
        $x++
    }

    if ($RecordCount -gt 0) {
        # Check for missing record tags and set defaults
            
        if ($RecordCount -gt 1) {
            $ValidationWarns.Add('Multiple TLSRPT records detected, this may cause unexpected behavior.') | Out-Null
            $TlsRptAnalysis.HasWarnings = $true
        }
        
        $ValidationWarnCount = ($Test.ValidationWarns | Measure-Object).Count
        $ValidationFailCount = ($Test.ValidationFails | Measure-Object).Count
        if ($ValidationFailCount -eq 0 -and $ValidationWarnCount -eq 0) {
            $ValidationPasses.Add('TLSRPT record is valid') | Out-Null
            $TlsRptAnalysis.IsValid = $true
        }
    }

    # Add the validation lists
    $TlsRptAnalysis.ValidationPasses = $ValidationPasses
    $TlsRptAnalysis.ValidationWarns = $ValidationWarns
    $TlsRptAnalysis.ValidationFails = $ValidationFails

    # Return MTA-STS analysis
    $TlsRptAnalysis
}