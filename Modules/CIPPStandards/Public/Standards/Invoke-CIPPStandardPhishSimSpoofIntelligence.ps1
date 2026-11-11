function Invoke-CIPPStandardPhishSimSpoofIntelligence {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) PhishSimSpoofIntelligence
    .SYNOPSIS
        (Label) Add allowed domains to Spoof Intelligence
    .DESCRIPTION
        (Helptext) This adds allowed domains to the Spoof Intelligence Allow/Block List.
        (DocsDescription) This adds allowed domains to the Spoof Intelligence Allow/Block List.
    .NOTES
        CAT
            Defender Standards
        TAG
        ADDEDCOMPONENT
            {"type":"switch","label":"Remove extra domains from the allow list","name":"standards.PhishSimSpoofIntelligence.RemoveExtraDomains","defaultValue":false,"required":false}
            {"type":"autoComplete","multiple":true,"creatable":true,"required":false,"label":"Allowed Domains","name":"standards.PhishSimSpoofIntelligence.AllowedDomains"}
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-03-28
        POWERSHELLEQUIVALENT
            New-TenantAllowBlockListSpoofItems
        RECOMMENDEDBY
        REQUIREDCAPABILITIES
            "EXCHANGE_S_STANDARD"
            "EXCHANGE_S_ENTERPRISE"
            "EXCHANGE_S_STANDARD_GOV"
            "EXCHANGE_S_ENTERPRISE_GOV"
            "EXCHANGE_LITE"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'PhishSimSpoofIntelligence' -TenantFilter $Tenant -Preset Exchange #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.
    # Fetch current Phishing Simulations Spoof Intelligence domains and ensure it is correctly configured
    try {
        # Only Allow entries count: a Block entry for a domain is the opposite of having it allowed,
        # and is an admin decision this standard must not remove.
        $DomainState = @(New-ExoRequest -TenantId $Tenant -cmdlet 'Get-TenantAllowBlockListSpoofItems' |
                Where-Object { $_.Action -eq 'Allow' } |
                Select-Object -Property Identity, SendingInfrastructure, SpoofType)
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the PhishSimSpoofIntelligence state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    # A domain is allowed when it has an Allow entry for both spoof types; add only the missing pairs
    $AddEntries = @(foreach ($Domain in @($Settings.AllowedDomains.value | Where-Object { $_ })) {
            foreach ($SpoofType in 'Internal', 'External') {
                if (-not ($DomainState | Where-Object { $_.SendingInfrastructure -eq $Domain -and $_.SpoofType -eq $SpoofType })) {
                    [PSCustomObject]@{ Domain = $Domain; SpoofType = $SpoofType }
                }
            }
        })
    [String[]]$AddDomain = $AddEntries.Domain | Select-Object -Unique

    if ($Settings.RemoveExtraDomains -eq $true) {
        $RemoveDomain = $DomainState | Where-Object { $_.SendingInfrastructure -notin $Settings.AllowedDomains.value } |
            Select-Object -Property Identity, SendingInfrastructure
    } else {
        $RemoveDomain = @()
    }

    $StateIsCorrect = ($AddDomain.Count -eq 0 -and $RemoveDomain.Count -eq 0)

    $CompareField = [PSCustomObject]@{
        'Missing Domains'   = $AddDomain -join ', '
        'Incorrect Domains' = $RemoveDomain.SendingInfrastructure -join ', '
    }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -message 'Spoof Intelligence Allow list already correctly configured' -sev Info
        } else {
            $BulkRequests = New-Object System.Collections.Generic.List[Hashtable]

            if ($Settings.RemoveExtraDomains -eq $true) {
                # Prepare removal requests
                if ($RemoveDomain.Count -gt 0) {
                    $BulkRequests.Add(@{
                            CmdletInput = @{
                                CmdletName = 'Remove-TenantAllowBlockListSpoofItems'
                                Parameters = @{ Identity = 'default'; Ids = $RemoveDomain.Identity }
                            }
                        })
                }
            }

            # Prepare addition requests
            foreach ($Entry in $AddEntries) {
                $BulkRequests.Add(@{
                        CmdletInput = @{
                            CmdletName = 'New-TenantAllowBlockListSpoofItems'
                            Parameters = @{ Identity = 'default'; Action = 'Allow'; SendingInfrastructure = $Entry.Domain; SpoofedUser = '*'; SpoofType = $Entry.SpoofType }
                        }
                    })
            }
            $RawExoRequest = New-ExoBulkRequest -tenantid $Tenant -cmdletArray @($BulkRequests)

            $LastError = $RawExoRequest | Select-Object -Last 1
            if ($LastError.error) {
                foreach ($ExoError in $LastError.error) {
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to process Spoof Intelligence Domain with error: $ExoError" -Sev Error
                }
            } else {
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Processed all Spoof Intelligence Domains successfully.' -Sev Info
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -message 'Spoof Intelligence Allow list is correctly configured' -sev Info
        } else {
            Write-StandardsAlert -message 'Spoof Intelligence Allow list is not correctly configured' -object $CompareField -tenant $Tenant -standardName 'PhishSimSpoofIntelligence' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -message 'Spoof Intelligence Allow list is not correctly configured' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            AllowedDomains = @($DomainState.SendingInfrastructure | Select-Object -Unique)
            IsCompliant    = [bool]$StateIsCorrect
        }
        $ExpectedValue = @{
            AllowedDomains = @($Settings.AllowedDomains.value)
            IsCompliant    = $true
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.PhishSimSpoofIntelligence' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}
