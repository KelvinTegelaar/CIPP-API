function Get-CIPPCyberInsuranceReport {
    <#
    .SYNOPSIS
        Builds the Cyber Insurance Readiness report for a tenant from its stored test results
    .PARAMETER TenantFilter
        The tenant to build the report for
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    # Coverage: Verified = read from the tenant, Partial = Microsoft side only, Attestation = answered by the MSP.
    $Catalog = @(
        @{ id = 1; question = 'MFA enforced for all email'; coverage = 'Verified'; testId = 'CyberIns_01' }
        @{ id = 2; question = 'MFA for remote network access (VPN, RDP)'; coverage = 'Attestation'; testId = 'CyberIns_02' }
        @{ id = 3; question = 'MFA for admin and privileged accounts'; coverage = 'Verified'; testId = 'CyberIns_03' }
        @{ id = 4; question = 'MFA for cloud and SaaS apps with sensitive data'; coverage = 'Partial'; testId = 'CyberIns_04' }
        @{ id = 5; question = 'MFA for backup systems'; coverage = 'Attestation'; testId = 'CyberIns_05' }
        @{ id = 6; question = 'Admin accounts separate from daily-use accounts'; coverage = 'Verified'; testId = 'CyberIns_06' }
        @{ id = 7; question = 'EDR or NGAV deployed on managed endpoints'; coverage = 'Partial'; testId = 'CyberIns_07' }
        @{ id = 8; question = 'Percentage of endpoints with EDR or NGAV'; coverage = 'Partial'; testId = 'CyberIns_08' }
        @{ id = 9; question = '24/7 staffed monitoring (SOC, MDR or MSSP)'; coverage = 'Attestation' }
        @{ id = 10; question = 'Email security and filtering'; coverage = 'Verified'; testId = 'CyberIns_10' }
        @{ id = 11; question = 'Firewalls deployed'; coverage = 'Attestation' }
        @{ id = 12; question = 'IDS/IPS or equivalent'; coverage = 'Attestation' }
        @{ id = 13; question = 'Logs centrally collected and monitored (SIEM or SOC)'; coverage = 'Partial'; testId = 'CyberIns_13' }
        @{ id = 14; question = 'Sensitive data encrypted at rest'; coverage = 'Partial'; testId = 'CyberIns_14' }
        @{ id = 15; question = 'Sensitive data encrypted in transit'; coverage = 'Partial'; testId = 'CyberIns_15' }
        @{ id = 16; question = 'All critical systems and data in scheduled backup'; coverage = 'Attestation' }
        @{ id = 17; question = 'Backup frequency'; coverage = 'Attestation' }
        @{ id = 18; question = 'Offline, air-gapped or isolated backup copy'; coverage = 'Attestation' }
        @{ id = 19; question = 'Immutable backups'; coverage = 'Attestation' }
        @{ id = 20; question = 'Backup credentials separate from production and domain admin'; coverage = 'Attestation'; testId = 'CyberIns_20' }
        @{ id = 21; question = 'Restore tested in the last 12 months'; coverage = 'Attestation' }
        @{ id = 22; question = 'Maximum days to deploy critical patches'; coverage = 'Partial'; testId = 'CyberIns_22' }
        @{ id = 23; question = 'Regular vulnerability scans'; coverage = 'Partial'; testId = 'CyberIns_23' }
        @{ id = 24; question = 'Annual phishing and security awareness training'; coverage = 'Attestation' }
        @{ id = 25; question = 'Wire and banking changes verified out-of-band'; coverage = 'Attestation' }
    )

    $Table = Get-CippTable -tablename 'CippTestResults'
    $Filter = "PartitionKey eq '{0}' and RowKey ge 'CyberIns_' and RowKey lt 'CyberIns``'" -f (ConvertTo-CIPPODataFilterValue -Value $TenantFilter)
    $ResultsById = @{}
    foreach ($Row in (Get-CIPPAzDataTableEntity @Table -Filter $Filter)) { $ResultsById[[string]$Row.RowKey] = $Row }

    $AttestationsByNumber = @{}
    $CustomerId = @(Get-Tenants -TenantFilter $TenantFilter -IncludeErrors)[0].customerId
    if ($CustomerId) {
        $AttestationTable = Get-CippTable -tablename 'CyberInsuranceAttestations'
        foreach ($Row in (Get-CIPPAzDataTableEntity @AttestationTable -Filter "PartitionKey eq '$CustomerId'")) { $AttestationsByNumber[[string]$Row.RowKey] = $Row }
    }

    $Counts = @{ Yes = 0; No = 0; Partial = 0; 'MSP attestation' = 0; 'Not licensed' = 0; 'No data' = 0; Reported = 0 }
    $Number = $Catalog.Count
    $Questions = @(foreach ($Entry in $Catalog) {
        $Result = if ($Entry.testId) { $ResultsById[$Entry.testId] }
        $Answer = if ($Entry.coverage -eq 'Attestation') {
            'MSP attestation'
        } else {
            switch ($Result.Status) {
                'Passed' { 'Yes' }
                'Failed' { 'No' }
                'Investigate' { 'Partial' }
                'Unlicensed' { 'Not licensed' }
                'Informational' { 'Reported' }
                default { 'No data' }
            }
        }
        $Counts[$Answer]++
        $Attested = $AttestationsByNumber["$($Entry.id)"]
        if ($Entry.coverage -eq 'Attestation' -and $Attested.Answer) { $Answer = [string]$Attested.Answer }
        [PSCustomObject]@{
            id           = "$($Entry.id)"
            number       = $Entry.id
            question     = $Entry.question
            coverage     = $Entry.coverage
            answer       = $Answer
            attestation  = [string]$Attested.Attestation
            attestedBy   = [string]$Attested.AttestedBy
            attestedDate = [string]$Attested.AttestedDate
            detail       = if ($Result.ResultMarkdown) { [string]$Result.ResultMarkdown } elseif ($Entry.testId) { 'This check has not run yet. Sync the report data to run it.' } else { 'This is not visible in Microsoft 365 and needs an MSP attestation.' }
        }
    }
    # Questions the MSP added for this tenant follow the application's own, oldest first.
        foreach ($Key in ([string[]]$AttestationsByNumber.Keys | Sort-Object)) {
            if ($Key -notlike 'Custom-*') { continue }
            $Added = $AttestationsByNumber[$Key]
            $Number++
            $Counts['MSP attestation']++
            [PSCustomObject]@{
                id           = $Key
                number       = $Number
                question     = [string]$Added.Question
                coverage     = 'Attestation'
                answer       = if ($Added.Answer) { [string]$Added.Answer } else { 'MSP attestation' }
                attestation  = [string]$Added.Attestation
                attestedBy   = [string]$Added.AttestedBy
                attestedDate = [string]$Added.AttestedDate
                detail       = 'This question was added by the MSP.'
            }
        })

    # The report is only as current as its oldest source, so the oldest refresh is the one shown.
    $SourceTypes = [System.Collections.Generic.HashSet[string]]::new([string[]]@(
            'MFAState', 'CASMailbox', 'ConditionalAccessPolicies', 'ServicePrincipals', 'Mailboxes', 'Roles', 'AppRoleAssignments',
            'ExoAntiPhishPolicies', 'ExoMalwareFilterPolicies', 'ExoAdminAuditLogConfig', 'ExoOrganizationConfig', 'ExoTransportConfig',
            'DomainAnalyser', 'ManagedDeviceProtectionStates', 'ManagedDeviceEncryptionStates', 'Devices', 'DefenderCVEs'
        ), [System.StringComparer]::OrdinalIgnoreCase)
    $Oldest = $null
    foreach ($CountRow in (Get-CIPPDbItem -TenantFilter $TenantFilter -CountsOnly)) {
        if (-not $CountRow.Timestamp -or -not $SourceTypes.Contains(($CountRow.RowKey -replace '-Count$', ''))) { continue }
        if ($null -eq $Oldest -or $CountRow.Timestamp -lt $Oldest) { $Oldest = $CountRow.Timestamp }
    }

    return [PSCustomObject]@{
        summary   = [PSCustomObject]@{
            yes             = $Counts.Yes
            no              = $Counts.No
            partial         = $Counts.Partial
            attestation     = $Counts.'MSP attestation'
            notLicensed     = $Counts.'Not licensed'
            noData          = $Counts.'No data'
            reported        = $Counts.Reported
            attested        = $AttestationsByNumber.Count
            testsRun        = $ResultsById.Count
            lastDataRefresh = if ($Oldest) { ([datetimeoffset]$Oldest).UtcDateTime.ToString('o') }
        }
        questions = @($Questions)
    }
}
