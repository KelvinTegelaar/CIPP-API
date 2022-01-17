param($tenant)

Import-Module '.\DNSHelper.psm1'

$Domain = $Tenant.Domain

Log-request -API 'DomainAnalyser' -tenant $tenant.tenant -message "Starting Processing of $($Tenant.Domain)" -sev Debug
$Result = [PSCustomObject]@{
    Tenant               = $tenant.tenant
    GUID                 = $($Tenant.Domain.Replace('.', ''))
    LastRefresh          = $(Get-Date (Get-Date).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%S.000Z')
    Domain               = $Domain
    AuthenticationType   = $Tenant.authenticationType
    IsAdminManaged       = $Tenant.isAdminManaged
    IsDefault            = $Tenant.isDefault
    IsInitial            = $Tenant.isInitial
    IsRoot               = $Tenant.isRoot
    IsVerified           = $Tenant.isVerified
    SupportedServices    = $Tenant.supportedServices
    ExpectedSPFRecord    = ''
    ActualSPFRecord      = ''
    SPFPassTest          = ''
    SPFPassAll           = ''
    ExpectedMXRecord     = ''
    ActualMXRecord       = ''
    MXPassTest           = ''
    DMARCPresent         = ''
    DMARCFullPolicy      = ''
    DMARCActionPolicy    = ''
    DMARCReportingActive = ''
    DMARCPercentagePass  = ''
    DNSSECPresent        = ''
    MailProvider         = ''
    DKIMEnabled          = ''
    Score                = ''
    MaximumScore         = 160
    ScorePercentage      = ''
    ScoreExplanation     = ''
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

$ScoreDomain = 0
# Setup Score Explanation
[System.Collections.ArrayList]$ScoreExplanation = @()

$MXRecord = Read-MXRecord -Domain $Domain
$Result.ExpectedSPFRecord = $MXRecord.ExpectedInclude

if ([string]::IsNullOrEmpty($MXRecord.MailProvider)) {
    $Result.MailProvider = 'Unknown'
}
else {
    $Result.MailProvider = $MXRecord.MailProvider.Name
}

# Get SPF Record
try {
    $SPFRecord = Read-SPFRecord -Domain $Domain
    if ($SPFRecord.RecordCount -gt 0) {
        $Result.ActualSPFRecord = $SPFRecord.Record
        if ($SPFRecord.RecordCount -eq 1) {
            $ScoreDomain += $Scores.SPFPresent
        }
    }
    else {
        $Result.ActualSPFRecord = 'No SPF Record'
        $ScoreExplanation.Add('No SPF Record Found') | Out-Null
    }
}
catch {
    Log-request -API 'DomainAnalyser' -tenant $tenant.tenant -message "Exception and Error while getting SPF Record with $($_.Exception.Message)" -sev Error
}
    
# Check SPF Record
$Result.SPFPassAll = $false
$Result.SPFPassTest = $false

foreach ($Validation in $SPFRecord.ValidationPasses) {
    if ($Validation -match 'Expected SPF') {
        $ScoreDomain += $Scores.SPFMSRecommended
        $Result.SPFPassTest = $true
        break
    }
}

# Check warning + fail counts to ensure all tests pass
$SPFWarnCount = $SPFRecord.ValidationWarns | Measure-Object | Select-Object -ExpandProperty Count
$SPFFailCount = $SPFRecord.ValidationFails | Measure-Object | Select-Object -ExpandProperty Count

if (($SPFWarnCount + $SPFFailCount) -eq 0) {
    $ScoreDomain += $Scores.SPFCorrectAll
    $Result.SPFPassAll = $true
}
    
# Check MX Record

$Result.MXPassTest = $false
# Check warning + fail counts to ensure all tests pass
$MXWarnCount = $MXRecord.ValidationWarns | Measure-Object | Select-Object -ExpandProperty Count
$MXFailCount = $MXRecord.ValidationFails | Measure-Object | Select-Object -ExpandProperty Count

if (($MXWarnCount + $MXFailCount) -eq 0) {
    $Result.MXPassTest = $true
    $ScoreDomain += $Scores.MXMSRecommended
}

# Get DMARC Record
try {
    $DMARCPolicy = Read-DmarcPolicy -Domain $Domain

    If ([string]::IsNullOrEmpty($DMARCPolicy.Record)) {
        $Result.DMARCPresent = $false
        $ScoreExplanation.Add('No DMARC Records Found') | Out-Null
    }
    else {
        $Result.DMARCPresent = $true
        $ScoreDomain += $Scores.DMARCPresent

        $Result.DMARCFullPolicy = $DMARCResults.Record
        if ($DMARCPolicy.Policy -eq 'reject' -and $DMARCPolicy.SubdomainPolicy -eq 'reject') { 
            $Result.DMARCActionPolicy = 'Reject'
            $ScoreDomain += $Scores.DMARCSetReject
        }
        if ($DMARCPolicy.Policy -eq 'none') { 
            $Result.DMARCActionPolicy = 'None'
            $ScoreExplanation.Add('DMARC is not being enforced') | Out-Null 
        }
        if ($DMARCPolicy.Policy -eq 'quarantine') {
            $Result.DMARCActionPolicy = 'Quarantine'
            $ScoreDomain += $Scores.DMARCSetQuarantine
            $ScoreExplanation.Add('DMARC Partially Enforced with quarantine') | Out-Null
        }
        $ReportEmailCount = $DMARCPolicy.ReportingEmails | Measure-Object | Select-Object -ExpandProperty Count
        if ($ReportEmailCount -gt 0) {
            $Result.DMARCReportingActive = $true
            $ScoreDomain += $Scores.DMARCReportingActive
        }
        else {
            $Result.DMARCReportingActive = $False
            $ScoreExplanation.Add('DMARC Reporting not Configured') | Out-Null
        }

        if ($DMARCPolicy.Percent -eq 100) {
            $Result.DMARCPercentagePass = $true
            $ScoreDomain += $Scores.DMARCPercentageGood
        }
        else {
            $Result.DMARCPercentagePass = $false
            $ScoreExplanation.Add('DMARC Not Checking All Messages') | Out-Null                
        }
    }
}
catch {
    Log-request -API 'DomainAnalyser' -tenant $tenant.tenant -message "Exception and Error while getting DMARC Record with $($_.Exception.Message)" -sev Error
}

# DNS Sec Check
try {
    $DNSSECResult = Test-DNSSEC -Domain $Domain
    $DNSSECFailCount = $DNSSECResult.ValidationFails | Measure-Object | Select-Object -ExpandProperty Count
    $DNSSECWarnCount = $DNSSECResult.ValidationFails | Measure-Object | Select-Object -ExpandProperty Count
    if (($DNSSECFailCount + $DNSSECWarnCount) -eq 0) {
        $Result.DNSSECPresent = $true
        $ScoreDomain += $Scores.DNSSECPresent
    }
    else {
        $Result.DNSSECPresent = $false
        $ScoreExplanation.Add('DNSSEC Not Configured or Enabled') | Out-Null 
    }
}
catch {
    Log-request -API 'DomainAnalyser' -tenant $tenant.tenant -message "Exception and Error while getting DNSSEC with $($_.Exception.Message)" -sev Error
}

# DKIM Check
try {
    $DkimRecord = Read-DkimRecord -Domain $Domain
    
    $DkimRecordCount = $DkimRecord.Records | Measure-Object | Select-Object -ExpandProperty Count
    $DkimFailCount = $DkimRecord.ValidationFails | Measure-Object | Select-Object -ExpandProperty Count
    $DkimWarnCount = $DkimRecord.ValidationWarns | Measure-Object | Select-Object -ExpandProperty Count
    if ($DkimRecordCount -gt 0 -and ($DkimFailCount + $DkimWarnCount) -eq 0) {
        $Result.DKIMEnabled = $true
        $ScoreDomain += $Scores.DKIMActiveAndWorking
    }
    else {
        $Result.DKIMEnabled = $false
        $ScoreExplanation.Add('DKIM Not Configured') | Out-Null 
    }
}
catch {
    Log-request -API 'DomainAnalyser' -tenant $tenant.tenant -message "DKIM Lookup Failed with $($_.Exception.Message)" -sev Error
}
# Final Score
$Result.Score = $ScoreDomain
$Result.ScorePercentage = [int](($Result.Score / $Result.MaximumScore) * 100)
$Result.ScoreExplanation = ($ScoreExplanation) -join ', '

# Final Write to Output
Log-request -API 'DomainAnalyser' -tenant $tenant.tenant -message "DNS Analyser Finished For $($Result.Domain)" -sev Info
Write-Output $Result

