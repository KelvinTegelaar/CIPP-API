param($tenant)

function Get-GoogleDNSQuery {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $Domain,

        [Parameter()]
        [string]
        $RecordType,

        [Parameter()]
        [bool]
        $FullResultRecord = $False
    )

    try {                
        $Results = Invoke-RestMethod -Uri "https://dns.google/resolve?name=$($Domain)&type=$($RecordType)" -Method Get
    }
    catch {
        Log-request -API "DomainAnalyser" -tenant $tenant -message "Get Google DNS Query Failed with $($_.Exception.Message)" -sev Debug
    }

    # Domain does not exist
    if ($Results.Status -ne 0) {
        return $null
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

$Domains = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/domains" -tenantid $Tenant | Where-Object { $_.id -notlike '*.onmicrosoft.com' }
Log-request -API "DomainAnalyser" -tenant $tenant -message "Found $($Domains.Count) domains to process" -sev Debug

$Final = foreach ($domain in $Domains) {
    Log-request -API "DomainAnalyser" -tenant $tenant -message "Starting Processing of $($domain.id)" -sev Debug
    $Result = [PSCustomObject]@{
        Tenant               = $tenant
        GUID                 = $($Domain.id.Replace('.', ''))
        LastRefresh          = $(Get-Date (Get-Date).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%S.000Z')
        Domain               = $Domain.id
        AuthenticationType   = $Domain.authenticationType
        IsAdminManaged       = $Domain.isAdminManaged
        IsDefault            = $domain.isDefault
        IsInitial            = $domain.isInitial
        IsRoot               = $domain.isRoot
        IsVerified           = $domain.isVerified
        SupportedServices    = $domain.supportedServices
        ExpectedSPFRecord    = ""
        ActualSPFRecord      = ""
        SPFPassTest          = ""
        SPFPassAll           = ""
        ExpectedMXRecord     = ""
        ActualMXRecord       = ""
        MXPassTest           = ""
        DMARCPresent         = ""
        DMARCFullPolicy      = ""
        DMARCActionPolicy    = ""
        DMARCReportingActive = ""
        DMARCPercentagePass  = ""
        DNSSECPresent        = ""
        MailProvider         = ""
        DKIMEnabled          = ""
        Score                = ""
        ScoreExplanation     = ""
    }

    $Scores = [PSCustomObject]@{
        SPFPresent           = 10
        SPFMSRecommended     = 10
        SPFCorrectAll        = 10
        MXMSRecommended      = 10
        DMARCPresent         = 10
        DMARCSetQuarantine   = 20
        DMARCSetReject       = 30
        DMARCReportingActive = 20
        DMARCPercentageGood  = 20
        DNSSECPresent        = 20
        DKIMActiveAndWorking = 20
    }

    $MaxPossibleScore = 140
    $ScoreDomain = 0
    # Setup Score Explanation
    [System.Collections.ArrayList]$ScoreExplanation = @()

    # Get 365 Service Configuration Records
    $ServiceConfigRecords = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/domains/$($domain.id)/serviceConfigurationRecords" -tenantid $Tenant

    $Result.ExpectedMXRecord = $ServiceConfigRecords | Where-Object { $_.RecordType -eq "MX" } | Select-Object -ExpandProperty MailExchange
    $Result.ExpectedSPFRecord = $ServiceConfigRecords | Where-Object { ($_.RecordType -eq "Txt") -and ($_.Text -like "*spf*") } | Select-Object -ExpandProperty Text

    # Get SPF Record
    try {
        $Results = Get-GoogleDNSQuery -Domain $domain.id -RecordType "TXT"
        $SPFResults = $Results | Where-Object { $_.Data -like '*spf1*' } | Select-Object -ExpandProperty Data
        if ($SPFResults.Count -gt 0) {
            $Result.ActualSPFRecord = $SPFResults | Where-Object { $_ -like '*spf1*' }
            $ScoreDomain += $Scores.SPFPresent
        }
        else {
            $Result.ActualSPFRecord = "No SPF Record"
            $ScoreExplanation.Add("No SPF Record Found") | Out-Null
        }
    }
    catch {
        Log-request -API "DomainAnalyser" -tenant $tenant -message "Exception and Error while getting SPF Record with $($_.Exception.Message)" -sev Error
    }
    
    # Check SPF Record
    $SPFMatch = $Result.ActualSPFRecord | Where-Object { $_ -like "$($Result.ExpectedSPFRecord)" }
    If (($SPFMatch | Measure-Object | Select-Object -ExpandProperty Count) -gt 0) {
        $ScoreDomain += $Scores.SPFMSRecommended
        $Result.SPFPassTest = $true
        if ($SPFMatch -like '*-all*') {
            $ScoreDomain += $Scores.SPFCorrectAll
            $Result.SPFPassAll = $true
        }
        else {
            $Result.SPFPassAll = $false
        }
    }
    else {
        if ($Result.ActualSPFRecord -like '*include:spf.protection.outlook.com*') {
            $ScoreDomain += $Scores.SPFMSRecommended
            $Result.SPFPassTest = $true
            if ($Result.ActualSPFRecord -like '*-all*') {
                $ScoreDomain += $Scores.SPFCorrectAll
                $Result.SPFPassAll = $true
            }
            else {
                $Result.SPFPassAll = $false
            }
        }
        else {
            $ScoreExplanation.Add("SPF Record is Misconfigured") | Out-Null 
            $Result.SPFPassTest = $false
            $Result.SPFPassAll = $false
        }

    }
    
    # Get MX Record
    try {
        $MXResults = Get-GoogleDNSQuery -domain $domain.id -RecordType "MX"
        $Result.ActualMXRecord = ($MXResults) -join ","
    }
    catch {
        Log-request -API "DomainAnalyser" -tenant $tenant -message "Exception and Error while getting MX Record with $($_.Exception.Message)" -sev Error
    }

    # Check MX Record
    $MXMatch = $Result.ActualMXRecord | Where-Object { $_ -like "*$($Result.ExpectedMXRecord)*" }
    If (($MXMatch | Measure-Object | Select-Object -ExpandProperty Count) -gt 0) {
        $Result.MXPassTest = $true
        $ScoreDomain += $Scores.MXMSRecommended
    }
    else { 
        $Result.MXPassTest = $false
        $ScoreExplanation.Add("MX Record does not match Microsoft's suggestion") | Out-Null 
    }

    # Get DMARC Record
    try {
        #$DMARCResults = Resolve-DnsName -Name "_dmarc.$($domain.id)" -Type TXT -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq "TXT" }
        $DMARCResults = Get-GoogleDNSQuery -Domain "_dmarc.$($domain.id)" -RecordType "TXT"
        If ([string]::IsNullOrEmpty($DMARCResults.data)) {
            $Result.DMARCPresent = $false
            $ScoreExplanation.Add("No DMARC Records Found") | Out-Null
        }
        else {
            $Result.DMARCPresent = $true
            $ScoreDomain += $Scores.DMARCPresent

            $Result.DMARCFullPolicy = $DMARCResults.data
            if ($Result.DMARCFullPolicy -like '*p=n*') { 
                $Result.DMARCActionPolicy = "None"
                $ScoreExplanation.Add("DMARC is not being enforced") | Out-Null 
            }
            if ($Result.DMARCFullPolicy -like '*p=q*') {
                $Result.DMARCActionPolicy = "Quarantine"
                $ScoreDomain += $Scores.DMARCSetQuarantine
                $ScoreExplanation.Add("DMARC Partially Enforced with quarantine") | Out-Null
            }
            if ($Result.DMARCFullPolicy -like '*p=r*') { 
                $Result.DMARCActionPolicy = "Reject"
                $ScoreDomain += $Scores.DMARCSetReject
            }
            if (($Result.DMARCFullPolicy -like '*rua*') -or ($Result.DMARCHFullPolicy -like '*ruf*')) {
                $Result.DMARCReportingActive = $true
                $ScoreDomain += $Scores.DMARCReportingActive
            }
            else {
                $Result.DMARCReportingActive = $False
                $ScoreExplanation.Add("DMARC Reporting not Configured") | Out-Null
            }
            if ($Result.DMARCFullPolicy -like '*pct=*') {
                if ($Result.DMARCFullPolicy -like '*pct=100*') {
                    $Result.DMARCPercentagePass = $true
                    $ScoreDomain += $Scores.DMARCPercentageGood
                }
                else {
                    $Result.DMARCPercentagePass = $false
                    $ScoreExplanation.Add("DMARC Not Checking All Messages") | Out-Null                
                } 
            }
            else {
                $Result.DMARCPercentagePass = $true 
                $ScoreDomain += $Scores.DMARCPercentageGood
            }
        }
    }
    catch {
        Log-request -API "DomainAnalyser" -tenant $tenant -message "Exception and Error while getting DMARC Record with $($_.Exception.Message)" -sev Error
    }

    # DNS Sec Check
    try {
        $DNSSECResult = Get-GoogleDNSQuery -Domain "$($domain.id)" -RecordType "SOA" -FullResultRecord $true
        if ($DNSSECResult.AD) {
            $Result.DNSSECPresent = $true
            $ScoreDomain += $Scores.DNSSECPresent
        }
        else {
            $Result.DNSSECPresent = $false
            $ScoreExplanation.Add("DNSSEC Not Configured or Enabled") | Out-Null 
        }
    }
    catch {
        Log-request -API "DomainAnalyser" -tenant $tenant -message "Exception and Error while getting DNSSEC with $($_.Exception.Message)" -sev Error
    }

    # DKIM Check
    try {
        # We can only really do Google and 365 DKIM so lets work out whether we are on Google or 365
        if ($ActualMXRecord -like '*protection.outlook.com*') {
            $Result.MailProvider = "Microsoft 365"
            $DKIMSelector = "selector1._domainkey.$($domain.id)"
        }
        
        if ($ActualMXRecord -like '*l.google.com*') {
            $Result.MailProvider = "Google"
            $DKIMSelector = "google._domainkey.$($domain.id)"
        }

        if([string]::IsNullOrEmpty($Result.MailProvider)) {
            $Result.MailProvider = "Unknown"
        }

        if ($Result.MailProvider -ne 'Unknown') {
            Log-Request -API "DomainAnalyser" -tenant $tenant -message "This is $($domain.id) with DKIM Selector of $($DKIMSelector)"
            $DKIMResult = Get-GoogleDNSQuery -Domain $DKIMSelector -RecordType "TXT"
            if ($DKIMResult.Data -like '*v=DKIM1*') {
                $Result.DKIMEnabled = $true
                $ScoreDomain += $Scores.DKIMActiveAndWorking
            }
            else {
                $Result.DKIMEnabled = $false
                $ScoreExplanation.Add("DKIM Not Configured") | Out-Null 
            }
        }

    }
    catch {
        Log-request -API "DomainAnalyser" -tenant $tenant -message "DKIM Lookup Failed with $($_.Exception.Message)" -sev Error
    }
    # Final Score
    $Result.Score = $ScoreDomain
    $Result.ScoreExplanation = ($ScoreExplanation) -join "<br />"

    # Final Write to Output
    Write-Output $Result
}

Log-request -API "DomainAnalyser" -tenant $tenant -message "DNS Analyser Finished with an output of $($Final.Count) result(s)" -sev Info
Write-Output $Final