function Invoke-CIPPStandardPhishingSimulations {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) PhishingSimulations
    .SYNOPSIS
        (Label) Phishing Simulation Configuration
    .DESCRIPTION
        (Helptext) This creates a phishing simulation policy that enables phishing simulations for the entire tenant.
        (DocsDescription) This creates a phishing simulation policy that enables phishing simulations for the entire tenant.
    .NOTES
        CAT
            Defender Standards
        TAG
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":true,"creatable":true,"required":true,"label":"Phishing Simulation Domains","name":"standards.PhishingSimulations.Domains"}
            {"type":"autoComplete","multiple":true,"creatable":true,"required":true,"label":"Phishing Simulation Sender IP Ranges","name":"standards.PhishingSimulations.SenderIpRanges"}
            {"type":"autoComplete","multiple":true,"creatable":true,"required":false,"label":"Phishing Simulation Urls","name":"standards.PhishingSimulations.PhishingSimUrls"}
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-03-27
        POWERSHELLEQUIVALENT
            New-TenantAllowBlockListItems, New-PhishSimOverridePolicy and New-ExoPhishSimOverrideRule
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/defender-standards#medium-impact
    #>

    param($Tenant, $Settings)
    $PolicyName = 'CIPPPhishSim'

    # Fetch current Phishing Simulations Policy settings and ensure it is correctly configured
    $PolicyState = New-ExoRequest -TenantId $Tenant -cmdlet 'Get-PhishSimOverridePolicy' |
    Where-Object -Property Name -EQ 'PhishSimOverridePolicy' |
    Select-Object -Property Identity,Name,Mode,Enabled

    $PolicyIsCorrect = ($PolicyState.Name -eq 'PhishSimOverridePolicy') -and ($PolicyState.Enabled -eq $true)

    # Fetch current Phishing Simulations Policy Rule settings and ensure it is correctly configured
    $RuleState = New-ExoRequest -TenantId $Tenant -cmdlet 'Get-ExoPhishSimOverrideRule' |
    Select-Object -Property Identity,Name,SenderIpRanges,Domains,SenderDomainIs

    [String[]]$AddSenderIpRanges = $Settings.SenderIpRanges.value | Where-Object { $_ -notin $RuleState.SenderIpRanges }
    if ($Settings.RemoveExtraUrls -eq $true) {
        [String[]]$RemoveSenderIpRanges = $RuleState.SenderIpRanges | Where-Object { $_ -notin $Settings.SenderIpRanges.value }
    } else {
        $RemoveSenderIpRanges = @()
    }

    [String[]]$AddDomains = $Settings.Domains.value | Where-Object { $_ -notin $RuleState.Domains }
    if ($Settings.RemoveExtraUrls -eq $true) {
        [String[]]$RemoveDomains = $RuleState.Domains | Where-Object { $_ -notin $Settings.Domains.value }
    } else {
        $RemoveDomains = @()
    }

    $RuleIsCorrect = ($RuleState.Name -like "*PhishSimOverr*") -and
    ($AddSenderIpRanges.Count -eq 0 -and $RemoveSenderIpRanges.Count -eq 0) -and
    ($AddDomains.Count -eq 0 -and $RemoveDomains.Count -eq 0)

    # Fetch current Phishing Simulations URLs and ensure it is correctly configured
    $SimUrlState = New-ExoRequest -TenantId $Tenant -cmdlet 'Get-TenantAllowBlockListItems' -cmdParams @{ListType = 'Url'; ListSubType = 'AdvancedDelivery'} |
    Select-Object -Property Value

    [String[]]$AddEntries = $Settings.PhishingSimUrls.value | Where-Object { $_ -notin $SimUrlState.value }
    if ($Settings.RemoveExtraUrls -eq $true) {
        [String[]]$RemoveEntries = $SimUrlState.value | Where-Object { $_ -notin $Settings.PhishingSimUrls.value }
    } else {
        $RemoveEntries = @()
    }

    $PhishingSimUrlsIsCorrect = ($AddEntries.Count -eq 0 -and $RemoveEntries.Count -eq 0)

    # Check state for all components
    $StateIsCorrect = $PolicyIsCorrect -and $RuleIsCorrect -and $PhishingSimUrlsIsCorrect

    $CompareField = [PSCustomObject]@{
        Domains         = $RuleState.Domains -join ', '
        SenderIpRanges  = $RuleState.SenderIpRanges -join ', '
        PhishingSimUrls = $SimUrlState.value -join ', '
    }

    If ($Settings.remediate -eq $true) {
        If ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -message 'Advanced Phishing Simulations already correctly configured' -sev Info
        } Else {
            # Remediate incorrect Phishing Simulations Policy
            If ($PolicyIsCorrect -eq $false) {
                If ($PolicyState.Name -eq 'PhishSimOverridePolicy') {
                    Try {
                        $null = New-ExoRequest -TenantId $Tenant -cmdlet 'Set-PhishSimOverridePolicy' -cmdParams @{Identity = $PolicyName; Enabled = $true}
                        Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Enabled Phishing Simulation override policy." -sev Info
                    } Catch {
                        Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Failed to enable Phishing Simulation override policy." -sev Error -LogData $_
                    }
                } Else {
                    Try {
                        $null = New-ExoRequest -TenantId $Tenant -cmdlet 'New-PhishSimOverridePolicy' -cmdParams @{Name = $PolicyName; Enabled = $true}
                        Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Created Phishing Simulation override policy." -sev Info
                    } Catch {
                        Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Failed to create Phishing Simulation override policy." -sev Error -LogData $_
                    }
                }
            }

            # Remediate incorrect Phishing Simulations Policy Rule
            If ($RuleIsCorrect -eq $false) {
                If ($RuleState.Name -like "*PhishSimOverr*") {
                    $cmdParams = @{
                        Identity = $RuleState.Identity
                        AddSenderIpRanges = $AddSenderIpRanges
                        AddDomains = $AddDomains
                        RemoveSenderIpRanges = $RemoveSenderIpRanges
                        RemoveDomains = $RemoveDomains
                    }
                    Try {
                        $null = New-ExoRequest -TenantId $Tenant -cmdlet 'Set-ExoPhishSimOverrideRule' -cmdParams $cmdParams
                        Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Updated Phishing Simulation override rule." -sev Info
                    } Catch {
                        Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Failed to update Phishing Simulation override rule." -sev Error -LogData $_
                    }
                } Else {
                    $cmdParams = @{
                        Name = $PolicyName
                        Policy = 'PhishSimOverridePolicy'
                        SenderIpRanges = $Settings.SenderIpRanges.value
                        Domains = $Settings.Domains.value
                    }
                    Try {
                        $null = New-ExoRequest -TenantId $Tenant -cmdlet 'New-ExoPhishSimOverrideRule' -cmdParams $cmdParams
                        Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Created Phishing Simulation override rule." -sev Info
                    } Catch {
                        Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Failed to create Phishing Simulation override rule." -sev Error -LogData $_
                    }
                }
            }

            # Remediate incorrect Phishing Simulations URLs
            If ($PhishingSimUrlsIsCorrect -eq $false) {
                $cmdParams = @{
                    ListType = 'Url'
                    ListSubType = 'AdvancedDelivery'
                }
                if ($Settings.RemoveExtraUrls -eq $true) {
                    # Remove entries that are not in the settings
                    If ($RemoveEntries.Count -gt 0) {
                        $cmdParams.Entries = $RemoveEntries
                        Try {
                            $null = New-ExoRequest -TenantId $Tenant -cmdlet 'Remove-TenantAllowBlockListItems' -cmdParams $cmdParams
                            Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Removed Phishing Simulation URLs from Allowlist." -sev Info
                        } Catch {
                            Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Failed to remove Phishing Simulation URLs from Allowlist." -sev Error -LogData $_
                        }
                    }
                }
                # Add entries that are in the settings
                If ($AddEntries.Count -gt 0) {
                    $cmdParams.Entries = $AddEntries
                    $cmdParams.NoExpiration = $true
                    $cmdParams.Allow = $true
                    Try {
                        $null = New-ExoRequest -TenantId $Tenant -cmdlet 'New-TenantAllowBlockListItems' -cmdParams $cmdParams
                        Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Added Phishing Simulation URLs to Allowlist." -sev Info
                    } Catch {
                        Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Failed to add Phishing Simulation URLs to Allowlist." -sev Error -LogData $_
                    }
                }
            }
        }
    }

    If ($Settings.alert -eq $true) {
        If ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -message 'Phishing Simulation Configuration is correctly configured' -sev Info
        } Else {
            Write-StandardsAlert -message 'Phishing Simulation Configuration is not correctly configured' -object $CompareField -tenant $Tenant -standardName 'PhishingSimulations' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -message 'Phishing Simulation Configuration is not correctly configured' -sev Info
        }
    }

    If ($Settings.report -eq $true) {
        $FieldValue = $StateIsCorrect ? $true : $CompareField
        Add-CIPPBPAField -FieldName 'PhishingSimulations' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
        Set-CIPPStandardsCompareField -FieldName 'standards.PhishingSimulations' -FieldValue $FieldValue -Tenant $Tenant
    }
}
