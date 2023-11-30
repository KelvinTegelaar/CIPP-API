param($DomainObject)

Import-Module DNSHealth

try {
    $ConfigTable = Get-CippTable -tablename Config
    $Filter = "PartitionKey eq 'Domains' and RowKey eq 'Domains'"
    $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter $Filter

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
        Add-CIPPAzDataTableEntity @ConfigTable -Entity $Config -Force
    }
}
catch {
    $Resolver = 'Google'
}
Set-DnsResolver -Resolver $Resolver

$Domain = $DomainObject.rowKey

try {
    $Tenant = $DomainObject.TenantDetails | ConvertFrom-Json -ErrorAction Stop
}
catch {
    $Tenant = @{Tenant = 'None' }
}

#Write-Host "$($DomainObject.TenantDetails)"

$Result = [PSCustomObject]@{
    Tenant               = $Tenant.Tenant
    GUID                 = $($Domain.Replace('.', ''))
    LastRefresh          = $(Get-Date (Get-Date).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%S.000Z')
    Domain               = $Domain
    ExpectedSPFRecord    = ''
    ActualSPFRecord      = ''
    SPFPassAll           = ''
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
    SPFCorrectAll        = 20
    MXRecommended        = 10
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
$ScoreExplanation = [System.Collections.Generic.List[string]]::new()

# Check MX Record
$MXRecord = Read-MXRecord -Domain $Domain -ErrorAction Stop

$Result.ExpectedSPFRecord = $MXRecord.ExpectedInclude
$Result.MXPassTest = $false

# Check fail counts to ensure all tests pass
#$MXWarnCount = $MXRecord.ValidationWarns | Measure-Object | Select-Object -ExpandProperty Count
$MXFailCount = $MXRecord.ValidationFails | Measure-Object | Select-Object -ExpandProperty Count

if ($MXFailCount -eq 0) {
    $Result.MXPassTest = $true
    $ScoreDomain += $Scores.MXRecommended
}
else {
    $ScoreExplanation.Add('MX record did not pass validation') | Out-Null
}

if ([string]::IsNullOrEmpty($MXRecord.MailProvider)) {
    $Result.MailProvider = 'Unknown'
}
else {
    $Result.MailProvider = $MXRecord.MailProvider.Name
}

# Get SPF Record
try {
    $SPFRecord = Read-SpfRecord -Domain $Domain -ErrorAction Stop
    if ($SPFRecord.RecordCount -gt 0) {
        $Result.ActualSPFRecord = $SPFRecord.Record
        if ($SPFRecord.RecordCount -eq 1) {
            $ScoreDomain += $Scores.SPFPresent
        }
        else {
            $ScoreExplanation.Add('Multiple SPF records detected') | Out-Null
        }
    }
    else {
        $Result.ActualSPFRecord = 'No SPF Record'
        $ScoreExplanation.Add('No SPF Record Found') | Out-Null
    }
}
catch {
    $Message = 'SPF Exception: {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message
    Write-LogMessage -API 'DomainAnalyser' -tenant $tenant.tenant -message $Message -sev Error
    throw $Message
}
    
# Check SPF Record
$Result.SPFPassAll = $false

# Check warning + fail counts to ensure all tests pass
#$SPFWarnCount = $SPFRecord.ValidationWarns | Measure-Object | Select-Object -ExpandProperty Count
$SPFFailCount = $SPFRecord.ValidationFails | Measure-Object | Select-Object -ExpandProperty Count

if ($SPFFailCount -eq 0) {
    $ScoreDomain += $Scores.SPFCorrectAll
    $Result.SPFPassAll = $true
}
else {
    $ScoreExplanation.Add('SPF record did not pass validation') | Out-Null
}

# Get DMARC Record
try {
    $DMARCPolicy = Read-DmarcPolicy -Domain $Domain -ErrorAction Stop

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
    $Message = 'DMARC Exception: {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message
    Write-LogMessage -API 'DomainAnalyser' -tenant $tenant.tenant -message $Message -sev Error
    throw $Message
}

# DNS Sec Check
try {
    $DNSSECResult = Test-DNSSEC -Domain $Domain -ErrorAction Stop
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
    $Message = 'DNSSEC Exception: {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message
    Write-LogMessage -API 'DomainAnalyser' -tenant $tenant.tenant -message $Message -sev Error
    throw $Message
}

# DKIM Check
try {
    $DkimParams = @{
        Domain = $Domain
    }
    if (![string]::IsNullOrEmpty($DomainObject.DkimSelectors)) {
        $DkimParams.Selectors = $DomainObject.DkimSelectors | ConvertFrom-Json
    }

    $DkimRecord = Read-DkimRecord @DkimParams -ErrorAction Stop
    
    $DkimRecordCount = $DkimRecord.Records | Measure-Object | Select-Object -ExpandProperty Count
    $DkimFailCount = $DkimRecord.ValidationFails | Measure-Object | Select-Object -ExpandProperty Count
    #$DkimWarnCount = $DkimRecord.ValidationWarns | Measure-Object | Select-Object -ExpandProperty Count
    if ($DkimRecordCount -gt 0 -and $DkimFailCount -eq 0) {
        $Result.DKIMEnabled = $true
        $ScoreDomain += $Scores.DKIMActiveAndWorking
    }
    else {
        $Result.DKIMEnabled = $false
        $ScoreExplanation.Add('DKIM Not Configured') | Out-Null 
    }
}
catch {
    $Message = 'DKIM Exception: {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message
    Write-LogMessage -API 'DomainAnalyser' -tenant $tenant.tenant -message $Message -sev Error
    throw $Message
}
# Final Score
$Result.Score = $ScoreDomain
$Result.ScorePercentage = [int](($Result.Score / $Result.MaximumScore) * 100)
$Result.ScoreExplanation = ($ScoreExplanation) -join ', '


$DomainObject.DomainAnalyser = ($Result | ConvertTo-Json -Compress).ToString()

# Final Write to Output
Write-LogMessage -API 'DomainAnalyser' -tenant $tenant.tenant -message "DNS Analyser Finished For $Domain" -sev Info

Write-Output $DomainObject