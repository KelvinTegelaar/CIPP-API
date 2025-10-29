function Push-DomainAnalyserDomain {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)
    $DomainTable = Get-CippTable -tablename 'Domains'
    $Filter = "PartitionKey eq 'TenantDomains' and RowKey eq '{0}'" -f $Item.RowKey
    $DomainObject = Get-CIPPAzDataTableEntity @DomainTable -Filter $Filter | Select-Object * -ExcludeProperty table

    try {
        $ConfigTable = Get-CippTable -tablename Config
        $Filter = "PartitionKey eq 'Domains' and RowKey eq 'Domains'"
        $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter $Filter

        $ValidResolvers = @('Google', 'CloudFlare', 'Quad9')
        if ($ValidResolvers -contains $Config.Resolver) {
            $Resolver = $Config.Resolver
        } else {
            $Resolver = 'Google'
            $Config = @{
                PartitionKey = 'Domains'
                RowKey       = 'Domains'
                Resolver     = $Resolver
            }
            Add-CIPPAzDataTableEntity @ConfigTable -Entity $Config -Force
        }
    } catch {
        $Resolver = 'Google'
    }
    Set-DnsResolver -Resolver $Resolver

    $Domain = $DomainObject.RowKey

    try {
        $Tenant = $DomainObject.TenantDetails | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $Tenant = @{ Tenant = 'None' }
    }

    $Result = [PSCustomObject]@{
        Tenant               = $Tenant.Tenant
        TenantID             = $Tenant.TenantGUID
        GUID                 = $($Domain.Replace('.', ''))
        LastRefresh          = $(Get-Date (Get-Date).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%S.000Z')
        Domain               = $Domain
        NSRecords            = (Read-NSRecord -Domain $Domain).Records
        ExpectedSPFRecord    = ''
        ActualSPFRecord      = ''
        SPFPassAll           = ''
        ActualMXRecords      = ''
        MXPassTest           = ''
        DMARCPresent         = ''
        DMARCFullPolicy      = ''
        DMARCActionPolicy    = ''
        DMARCReportingActive = ''
        DMARCPercentagePass  = ''
        DNSSECPresent        = ''
        MailProvider         = ''
        DKIMEnabled          = ''
        DKIMRecords          = ''
        MSCNAMEDKIMSelectors = ''
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

    #Region MX Check
    $MXRecord = Read-MXRecord -Domain $Domain -ErrorAction Stop

    $Result.ExpectedSPFRecord = $MXRecord.ExpectedInclude
    $Result.MXPassTest = $false
    $Result.ActualMXRecords = $MXRecord.Records

    # Check fail counts to ensure all tests pass
    #$MXWarnCount = $MXRecord.ValidationWarns | Measure-Object | Select-Object -ExpandProperty Count
    $MXFailCount = $MXRecord.ValidationFails | Measure-Object | Select-Object -ExpandProperty Count

    if ($MXFailCount -eq 0) {
        $Result.MXPassTest = $true
        $ScoreDomain += $Scores.MXRecommended
    } else {
        $ScoreExplanation.Add('MX record did not pass validation') | Out-Null
    }

    if ([string]::IsNullOrEmpty($MXRecord.MailProvider)) {
        $Result.MailProvider = 'Unknown'
    } else {
        $Result.MailProvider = $MXRecord.MailProvider.Name
    }
    #EndRegion MX Check

    #Region SPF Check
    try {
        $SPFRecord = Read-SpfRecord -Domain $Domain -ErrorAction Stop
        if ($SPFRecord.RecordCount -gt 0) {
            $Result.ActualSPFRecord = $SPFRecord.Record
            if ($SPFRecord.RecordCount -eq 1) {
                $ScoreDomain += $Scores.SPFPresent
            } else {
                $ScoreExplanation.Add('Multiple SPF records detected') | Out-Null
            }
        } else {
            $Result.ActualSPFRecord = 'No SPF Record'
            $ScoreExplanation.Add('No SPF Record Found') | Out-Null
        }
    } catch {
        $Message = 'SPF Error'
        Write-LogMessage -API 'DomainAnalyser' -tenant $DomainObject.TenantId -message $Message -LogData (Get-CippException -Exception $_) -sev Error
    }


    # Check warning + fail counts to ensure all tests pass
    #$SPFWarnCount = $SPFRecord.ValidationWarns | Measure-Object | Select-Object -ExpandProperty Count
    $SPFFailCount = $SPFRecord.ValidationFails | Measure-Object | Select-Object -ExpandProperty Count
    $Result.SPFPassAll = $false

    if ($SPFFailCount -eq 0) {
        $ScoreDomain += $Scores.SPFCorrectAll
        $Result.SPFPassAll = $true
    } else {
        $ScoreExplanation.Add('SPF record did not pass validation') | Out-Null
    }
    #EndRegion SPF Check

    #Region DMARC Check
    try {
        $DMARCPolicy = Read-DmarcPolicy -Domain $Domain -ErrorAction Stop

        If ([string]::IsNullOrEmpty($DMARCPolicy.Record)) {
            $Result.DMARCPresent = $false
            $ScoreExplanation.Add('No DMARC Records Found') | Out-Null
        } else {
            $Result.DMARCPresent = $true
            $ScoreDomain += $Scores.DMARCPresent

            $Result.DMARCFullPolicy = $DMARCPolicy.Record
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
            } else {
                $Result.DMARCReportingActive = $False
                $ScoreExplanation.Add('DMARC Reporting not Configured') | Out-Null
            }

            if ($DMARCPolicy.Percent -eq 100) {
                $Result.DMARCPercentagePass = $true
                $ScoreDomain += $Scores.DMARCPercentageGood
            } else {
                $Result.DMARCPercentagePass = $false
                $ScoreExplanation.Add('DMARC Not Checking All Messages') | Out-Null
            }
        }
    } catch {
        $Message = 'DMARC Error'
        Write-LogMessage -API 'DomainAnalyser' -tenant $DomainObject.TenantId -message $Message -LogData (Get-CippException -Exception $_) -sev Error
        #return $Message
    }
    #EndRegion DMARC Check

    #Region DNS Sec Check
    try {
        $DNSSECResult = Test-DNSSEC -Domain $Domain -ErrorAction Stop
        $DNSSECFailCount = $DNSSECResult.ValidationFails | Measure-Object | Select-Object -ExpandProperty Count
        $DNSSECWarnCount = $DNSSECResult.ValidationFails | Measure-Object | Select-Object -ExpandProperty Count
        if (($DNSSECFailCount + $DNSSECWarnCount) -eq 0) {
            $Result.DNSSECPresent = $true
            $ScoreDomain += $Scores.DNSSECPresent
        } else {
            $Result.DNSSECPresent = $false
            $ScoreExplanation.Add('DNSSEC Not Configured or Enabled') | Out-Null
        }
    } catch {
        $Message = 'DNSSEC Error'
        Write-LogMessage -API 'DomainAnalyser' -tenant $DomainObject.TenantId -message $Message -LogData (Get-CippException -Exception $_) -sev Error
        #return $Message
    }
    #EndRegion DNS Sec Check

    #Region DKIM Check
    try {
        $DkimParams = @{
            Domain                       = $Domain
            FallbackToMicrosoftSelectors = $true
        }
        if (![string]::IsNullOrEmpty($DomainObject.DkimSelectors)) {
            $DkimParams.Selectors = $DomainObject.DkimSelectors | ConvertFrom-Json
        }
        # Check if its a onmicrosoft.com domain and add special selectors for these
        if ($Domain -match 'onmicrosoft.com' -and $Domain -notmatch 'mail.onmicrosoft.com') {
            $DKIMSelector1Value = "selector1-$($Domain -replace '\.', '-' )"
            $DKIMSelector2Value = "selector2-$($Domain -replace '\.', '-' )"
            $DkimParams.Add('Selectors', @("$DKIMSelector1Value", "$DKIMSelector2Value"))
        }

        $DkimRecord = Read-DkimRecord @DkimParams -ErrorAction Stop

        $DkimRecordCount = $DkimRecord.Records | Measure-Object | Select-Object -ExpandProperty Count
        $DkimFailCount = $DkimRecord.ValidationFails | Measure-Object | Select-Object -ExpandProperty Count
        #$DkimWarnCount = $DkimRecord.ValidationWarns | Measure-Object | Select-Object -ExpandProperty Count
        if ($DkimRecordCount -gt 0 -and $DkimFailCount -eq 0) {
            $Result.DKIMEnabled = $true
            $ScoreDomain += $Scores.DKIMActiveAndWorking
            $Result.DKIMRecords = $DkimRecord.Records | Select-Object Selector, Record
        } else {
            $Result.DKIMEnabled = $false
            $ScoreExplanation.Add('DKIM Not Configured') | Out-Null
        }
    } catch {
        $Message = 'DKIM Exception'
        Write-LogMessage -API 'DomainAnalyser' -tenant $DomainObject.TenantId -message $Message -LogData (Get-CippException -Exception $_) -sev Error
        #return $Message
    }
    #EndRegion DKIM Check

    #Region MSCNAME DKIM Records
    # Get Microsoft DKIM CNAME selector Records
    # Ugly, but i needed to create a scope/loop i could break out of without breaking the rest of the function
    foreach ($d in $Domain) {
        try {
            # Test if DKIM is enabled, skip domain if it is
            if ($Result.DKIMEnabled -eq $true) {
                continue
            }
            # Test if its a onmicrosoft.com domain, skip domain if it is
            if ($Domain -match 'onmicrosoft.com') {
                continue
            }
            # Test if there are already MSCNAME values set, skip domain if there is
            if ($null -ne $DomainObject.DomainAnalyser) {
                $CurrentMSCNAMEInfo = ConvertFrom-Json $DomainObject.DomainAnalyser -Depth 10
                if (![string]::IsNullOrWhiteSpace($CurrentMSCNAMEInfo.MSCNAMEDKIMSelectors.selector1.Value) -and
                    ![string]::IsNullOrWhiteSpace($CurrentMSCNAMEInfo.MSCNAMEDKIMSelectors.selector2.Value)) {
                    $Result.MSCNAMEDKIMSelectors = $CurrentMSCNAMEInfo.MSCNAMEDKIMSelectors
                    continue
                }
            }

            # Get the DKIM record from EXO. This is the only way to get the correct values for the MSCNAME records since the new format was introduced in May 2025.
            $DKIM = (New-ExoRequest -tenantid $Tenant.Tenant -cmdlet 'Get-DkimSigningConfig' -Select 'Domain,Selector1CNAME,Selector2CNAME') | Where-Object { $_.Domain -eq $Domain }

            # If no DKIM signing record is found, create a new disabled one
            if ($null -eq $DKIM) {
                Write-Information 'No DKIM record found in EXO - Creating new signing'
                $NewDKIMSigningRequest = New-ExoRequest -tenantid $Tenant.Tenant -cmdlet 'New-DkimSigningConfig' -cmdParams @{  KeySize = 2048; DomainName = $Domain; Enabled = $false }
                $Selector1Value = $NewDKIMSigningRequest.Selector1CNAME
                $Selector2Value = $NewDKIMSigningRequest.Selector2CNAME
            } else {
                $Selector1Value = $DKIM.Selector1CNAME
                $Selector2Value = $DKIM.Selector2CNAME
            }


            # Create the MSCNAME object
            $MSCNAMERecords = [PSCustomObject]@{
                Domain    = $Domain
                selector1 = @{
                    Hostname = 'selector1._domainkey'
                    Value    = $Selector1Value
                }
                selector2 = @{
                    Hostname = 'selector2._domainkey'
                    Value    = $Selector2Value
                }
            }
            $Result.MSCNAMEDKIMSelectors = $MSCNAMERecords
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'DomainAnalyser' -tenant $DomainObject.TenantId -message "MS CNAME DKIM error: $($ErrorMessage.NormalizedError)" -LogData $ErrorMessage -sev Error
        }
    }
    #EndRegion MSCNAME DKIM Records
    # Final Score
    $Result.Score = $ScoreDomain
    $Result.ScorePercentage = [int](($Result.Score / $Result.MaximumScore) * 100)
    $Result.ScoreExplanation = ($ScoreExplanation) -join ', '

    $Json = (ConvertTo-Json -InputObject $Result -Depth 5 -Compress).ToString()

    if ($DomainObject.PSObject.Properties.Name -notcontains 'DomainAnalyser') {
        $DomainObject | Add-Member -MemberType NoteProperty -Name DomainAnalyser -Value $Json
    } else {
        $DomainObject.DomainAnalyser = $Json
    }

    try {
        $DomainTable.Entity = $DomainObject
        $DomainTable.Force = $true
        Add-CIPPAzDataTableEntity @DomainTable -Entity $DomainObject -Force

        # Final Write to Output
        Write-LogMessage -API 'DomainAnalyser' -tenant $DomainObject.TenantId -message "DNS Analyser Finished For $Domain" -sev Info
    } catch {
        Write-LogMessage -API 'DomainAnalyser' -tenant $DomainObject.TenantId -message "Error saving domain $Domain to table " -sev Error -LogData (Get-CippException -Exception $_)
    }
    return $null
}
