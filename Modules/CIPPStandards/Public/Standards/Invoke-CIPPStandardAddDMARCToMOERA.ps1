function Invoke-CIPPStandardAddDMARCToMOERA {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AddDMARCToMOERA
    .SYNOPSIS
        (Label) Enables DMARC on MOERA (onmicrosoft.com) domains
    .DESCRIPTION
        (Helptext) ** Remediation is not available ** Note: requires 'Domain Name Administrator' GDAP role. This should be enabled even if the MOERA (onmicrosoft.com) domains is not used for sending. Enabling this prevents email spoofing. The default value is 'v=DMARC1; p=reject;' recommended because the domain is only used within M365 and reporting is not needed. Omitting pct tag default to 100%
        (DocsDescription) \*\* Remediation is not available \*\* Note: requires 'Domain Name Administrator' GDAP role. Adds a DMARC record to MOERA (onmicrosoft.com) domains. This should be enabled even if the MOERA (onmicrosoft.com) domains is not used for sending. Enabling this prevents email spoofing. The default record is 'v=DMARC1; p=reject;' recommended because the domain is only used within M365 and reporting is not needed. Omitting pct tag default to 100%
    .NOTES
        CAT
            Global Standards
        TAG
            "CIS M365 5.0 (2.1.10)"
            "Security"
            "PhishingProtection"
        EXECUTIVETEXT
            Implements advanced email security for Microsoft's default domain names (onmicrosoft.com) to prevent criminals from impersonating your organization. This blocks fraudulent emails that could damage your company's reputation and protects partners and customers from phishing attacks using your domain names.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":true,"required":false,"placeholder":"v=DMARC1; p=reject; (recommended)","label":"Value","name":"standards.AddDMARCToMOERA.RecordValue","options":[{"label":"v=DMARC1; p=reject; (recommended)","value":"v=DMARC1; p=reject;"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-06-16
        POWERSHELLEQUIVALENT
            Portal only
        RECOMMENDEDBY
            "CIS"
            "Microsoft"
        DISABLEDFEATURES
            {"remediate":true}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    #$Rerun -Type Standard -Tenant $Tenant -API 'AddDMARCToMOERA' -Settings $Settings

    $RecordModel = [PSCustomObject]@{
        HostName = '_dmarc'
        TtlValue = 3600
        Type     = 'TXT'
        Value    = $Settings.RecordValue.Value ?? 'v=DMARC1; p=reject;'
    }

    # Get all fallback domains (onmicrosoft.com domains) and check if the DMARC record is set correctly
    try {
        $DomainsResponse = New-GraphGetRequest -TenantID $Tenant -Uri 'https://graph.microsoft.com/beta/domains'
        Write-Warning ($DomainsResponse | ConvertTo-Json -Depth 5)
        $Domains = @($DomainsResponse | Where-Object { $_.id -like '*.onmicrosoft.com' } | ForEach-Object { $_.id })
        Write-Information "Detected $($Domains.Count) MOERA domains: $($Domains -join ', ')"

        $CurrentInfo = foreach ($Domain in $Domains) {
            # Get current DNS records that matches _dmarc hostname and TXT type
            $RecordsResponse = New-GraphGetRequest -TenantID $Tenant -Uri "https://graph.microsoft.com/beta/domains/$($Domain)/serviceConfigurationRecords"
            $AllRecords = @($RecordsResponse)
            $CurrentRecords = $AllRecords | Where-Object {
                $_.recordType -ieq 'Txt' -and ($_.label -ieq '_dmarc' -or $_.label -ieq "_dmarc.$($Domain)")
            }
            Write-Information "Found $($CurrentRecords.count) DMARC records for domain $($Domain)"

            if ($CurrentRecords.count -eq 0) {
                #record not found, return a model with Match set to false
                [PSCustomObject]@{
                    DomainName    = $Domain
                    Match         = $false
                    CurrentRecord = $null
                }
            } else {
                foreach ($CurrentRecord in $CurrentRecords) {
                    # Create variable matching the RecordModel used for comparison
                    $CurrentRecordModel = [PSCustomObject]@{
                        HostName = '_dmarc'
                        TtlValue = $CurrentRecord.ttl
                        Type     = 'TXT'
                        Value    = $CurrentRecord.text
                    }

                    # Compare the current record with the expected record model
                    if (!(Compare-Object -ReferenceObject $RecordModel -DifferenceObject $CurrentRecordModel -Property HostName, TtlValue, Type, Value)) {
                        [PSCustomObject]@{
                            DomainName    = $Domain
                            Match         = $true
                            CurrentRecord = [PSCustomObject]@{
                                HostName = '_dmarc'
                                TtlValue = $CurrentRecord.ttl
                                Type     = 'TXT'
                                Value    = $CurrentRecord.text
                            }
                        }
                    } else {
                        [PSCustomObject]@{
                            DomainName    = $Domain
                            Match         = $false
                            CurrentRecord = [PSCustomObject]@{
                                HostName = '_dmarc'
                                TtlValue = $CurrentRecord.ttl
                                Type     = 'TXT'
                                Value    = $CurrentRecord.text
                            }
                        }
                    }
                }
            }
        }
        # Check if match is true and there is only one DMARC record for each domain
        $StateIsCorrect = $false -notin $CurrentInfo.Match -and $CurrentInfo.Count -eq $Domains.Count

        $CurrentValue = if ($StateIsCorrect) { [PSCustomObject]@{'state' = 'Configured correctly' } } else { [PSCustomObject]@{'MissingDMARC' = @($CurrentInfo | Where-Object -Property Match -EQ $false | Select-Object -ExpandProperty DomainName) } }
        $ExpectedValue = [PSCustomObject]@{'state' = 'Configured correctly' }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        if ($_.Exception.Message -like '*403*') {
            $Message = "AddDMARCToMOERA: Insufficient permissions. Please ensure the tenant GDAP relationship includes the 'Domain Name Administrator' role: $($ErrorMessage.NormalizedError)"
        } else {
            $Message = "Failed to get dns records for MOERA domains: $($ErrorMessage.NormalizedError)"
        }
        Write-LogMessage -API 'Standards' -tenant $tenant -message $Message -sev Error -LogData $ErrorMessage
        return $Message
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DMARC record is already set for all MOERA (onmicrosoft.com) domains.' -sev Info
        } else {
            $UniqueDomains = ($CurrentInfo | Sort-Object -Property DomainName -Unique)
            $NotSetDomains = @($UniqueDomains | ForEach-Object { if ($_.Match -eq $false -or ($CurrentInfo | Where-Object -Property DomainName -EQ $_.DomainName).Count -eq 1) { $_.DomainName } })
            $Message = "DMARC record is not set for $($NotSetDomains.count) of $($UniqueDomains.count) MOERA (onmicrosoft.com) domains."

            Write-StandardsAlert -message $Message -object @{MissingDMARC = ($NotSetDomains -join ', ') } -tenant $tenant -standardName 'AddDMARCToMOERA' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "$Message. Missing for: $($NotSetDomains -join ', ')" -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.AddDMARCToMOERA' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'AddDMARCToMOERA' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
