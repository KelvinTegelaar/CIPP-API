function Invoke-CIPPStandardAddDMARCToMOERA {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AddDMARCToMOERA
    .SYNOPSIS
        (Label) Enables DMARC on MOERA (onmicrosoft.com) domains
    .DESCRIPTION
        (Helptext) Note: requires 'Domain Name Administrator' GDAP role. This should be enabled even if the MOERA (onmicrosoft.com) domains is not used for sending. Enabling this prevents email spoofing. The default value is 'v=DMARC1; p=reject;' recommended because the domain is only used within M365 and reporting is not needed. Omitting pct tag default to 100%
        (DocsDescription) Note: requires 'Domain Name Administrator' GDAP role. Adds a DMARC record to MOERA (onmicrosoft.com) domains. This should be enabled even if the MOERA (onmicrosoft.com) domains is not used for sending. Enabling this prevents email spoofing. The default record is 'v=DMARC1; p=reject;' recommended because the domain is only used within M365 and reporting is not needed. Omitting pct tag default to 100%
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
        Value    = $Settings.RecordValue.Value ?? "v=DMARC1; p=reject;"
    }

    # Get all fallback domains (onmicrosoft.com domains) and check if the DMARC record is set correctly
    try {
        $Domains = New-GraphGetRequest -scope 'https://admin.microsoft.com/.default' -TenantID $Tenant -Uri 'https://admin.microsoft.com/admin/api/Domains/List' | Where-Object -Property Name -like "*.onmicrosoft.com"

        $CurrentInfo = $Domains | ForEach-Object {
            # Get current DNS records that matches _dmarc hostname and TXT type
            $CurrentRecords = New-GraphGetRequest -scope 'https://admin.microsoft.com/.default' -TenantID $Tenant -Uri "https://admin.microsoft.com/admin/api/Domains/Records?domainName=$($_.Name)" | Select-Object -ExpandProperty DnsRecords | Where-Object { $_.HostName -eq $RecordModel.HostName -and $_.Type -eq $RecordModel.Type }

            if ($CurrentRecords.count -eq 0) {
                #record not found, return a model with Match set to false
                [PSCustomObject]@{
                    DomainName      = $_.Name
                    Match           = $false
                    CurrentRecord   = $null
                }
            } else {
                foreach ($CurrentRecord in $CurrentRecords) {
                    # Create variable matching the RecordModel used for comparison
                    $CurrentRecordModel = [PSCustomObject]@{
                        HostName = $CurrentRecord.HostName
                        TtlValue = $CurrentRecord.TtlValue
                        Type     = $CurrentRecord.Type
                        Value    = $CurrentRecord.Value
                    }

                    # Compare the current record with the expected record model
                    if (!(Compare-Object -ReferenceObject $RecordModel -DifferenceObject $CurrentRecordModel -Property HostName, TtlValue, Type, Value)) {
                        [PSCustomObject]@{
                            DomainName      = $_.Name
                            Match           = $true
                            CurrentRecord   = $CurrentRecord
                        }
                    } else {
                        [PSCustomObject]@{
                            DomainName      = $_.Name
                            Match           = $false
                            CurrentRecord   = $CurrentRecord
                        }
                    }
                }
            }
        }
        # Check if match is true and there is only one DMARC record for the domain
        $StateIsCorrect = $false -notin $CurrentInfo.Match -and $CurrentInfo.Count -eq 1
    } catch {
        if ($_.Exception.Message -like '*403*') {
            $Message = "AddDMARCToMOERA: Insufficient permissions. Please ensure the tenant GDAP relationship includes the 'Domain Name Administrator' role: $(Get-NormalizedError -message $_.Exception.message)"
        }
        else {
            $Message = "Failed to get dns records for MOERA domains: $(Get-NormalizedError -message $_.Exception.message)"
        }
        Write-LogMessage -API 'Standards' -tenant $tenant -message $Message -sev Error
        throw $Message
    }

    If ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DMARC record is already set for all MOERA (onmicrosoft.com) domains.' -sev Info
        }
        else {
            # Loop through each domain and set the DMARC record, existing misconfigured records and duplicates will be deleted
            foreach ($Domain in ($CurrentInfo | Sort-Object -Property DomainName -Unique)) {
                try {
                    foreach ($Record in ($CurrentInfo | Where-Object -Property DomainName -eq $Domain.DomainName)) {
                        if ($Record.CurrentRecord) {
                            New-GraphPOSTRequest -tenantid $tenant -scope 'https://admin.microsoft.com/.default' -Uri "https://admin.microsoft.com/admin/api/Domains/Record?domainName=$($Domain.DomainName)" -Body ($Record.CurrentRecord | ConvertTo-Json -Compress) -AddedHeaders @{'x-http-method-override' = 'Delete'}
                            Write-LogMessage -API 'Standards' -tenant $tenant -message "Deleted incorrect DMARC record for domain $($Domain.DomainName)" -sev Info
                        }
                        New-GraphPOSTRequest -tenantid $tenant -scope 'https://admin.microsoft.com/.default' -type "PUT" -Uri "https://admin.microsoft.com/admin/api/Domains/Record?domainName=$($Domain.DomainName)" -Body (@{RecordModel = $RecordModel} | ConvertTo-Json -Compress)
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Set DMARC record for domain $($Domain.DomainName)" -sev Info
                    }
                }
                catch {
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set DMARC record for domain $($Domain.DomainName): $(Get-NormalizedError -message $_.Exception.message)" -sev Error
                }
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DMARC record is already set for all MOERA (onmicrosoft.com) domains.' -sev Info
        } else {
            $UniqueDomains = ($CurrentInfo | Sort-Object -Property DomainName -Unique)
            $NotSetDomains = @($UniqueDomains | ForEach-Object {if ($_.Match -eq $false -or ($CurrentInfo | Where-Object -Property DomainName -eq $_.DomainName).Count -eq 1) { $_.DomainName } })
            $Message = "DMARC record is not set for $($NotSetDomains.count) of $($UniqueDomains.count) MOERA (onmicrosoft.com) domains."

            Write-StandardsAlert -message $Message -object @{MissingDMARC = ($NotSetDomains -join ', ')} -tenant $tenant -standardName 'AddDMARCToMOERA' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "$Message. Missing for: $($NotSetDomains -join ', ')" -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        set-CIPPStandardsCompareField -FieldName 'standards.AddDMARCToMOERA' -FieldValue $StateIsCorrect -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'AddDMARCToMOERA' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
