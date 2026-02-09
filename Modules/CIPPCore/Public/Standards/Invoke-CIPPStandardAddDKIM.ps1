function Invoke-CIPPStandardAddDKIM {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AddDKIM
    .SYNOPSIS
        (Label) Enables DKIM for all domains that currently support it
    .DESCRIPTION
        (Helptext) Enables DKIM for all domains that currently support it
        (DocsDescription) Enables DKIM for all domains that currently support it
    .NOTES
        CAT
            Exchange Standards
        TAG
            "CIS M365 5.0 (2.1.9)"
        EXECUTIVETEXT
            Enables email authentication technology that digitally signs outgoing emails to verify they actually came from your organization. This prevents email spoofing, improves email deliverability, and protects the company's reputation by ensuring recipients can trust emails from your domains.
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2023-03-14
        POWERSHELLEQUIVALENT
            New-DkimSigningConfig and Set-DkimSigningConfig
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    #$Rerun -Type Standard -Tenant $Tenant -API 'AddDKIM' -Settings $Settings
    $TestResult = Test-CIPPStandardLicense -StandardName 'AddDKIM' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    $DkimRequest = @(
        @{
            CmdletInput = @{
                CmdletName = 'Get-AcceptedDomain'
                Parameters = @{}
            }
        },
        @{
            CmdletInput = @{
                CmdletName = 'Get-DkimSigningConfig'
                Parameters = @{}
            }
        }
    )

    $BatchResults = New-ExoBulkRequest -tenantid $Tenant -cmdletArray $DkimRequest -useSystemMailbox $true

    # Check for errors in the batch results. Cannot continue if there are errors.
    $ErrorCounter = 0
    $ErrorMessages = [System.Collections.Generic.List[string]]::new()
    foreach ($Result in $BatchResults) {
        if ($Result.error) {
            $ErrorCounter++
            $ErrorMessage = Get-NormalizedError -Message $Result.error
            $ErrorMessages.Add($ErrorMessage)
        }
    }
    if ($ErrorCounter -gt 0) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to get DKIM config. Error: $($ErrorMessages -join ', ')" -sev Error
        return
    }

    # Same exclusions also found in Push-DomainAnalyserTenant
    $ExclusionDomains = @(
        '*.microsoftonline.com'
        '*.mail.onmicrosoft.com'
        '*.exclaimer.cloud'
        '*.excl.cloud'
        '*.codetwo.online'
        '*.call2teams.com'
        '*.signature365.net'
        '*.myteamsconnect.io'
        '*.teams.dstny.com'
        '*.msteams.8x8.com'
        '*.ucconnect.co.uk'
        '*.teams-sbc.dk'
    )

    $AllDomains = foreach ($DomainName in ($BatchResults | Where-Object { $_.DomainName }).DomainName) {
        $Domain = $DomainName
        foreach ($ExclusionDomain in $ExclusionDomains) {
            if ($Domain -like $ExclusionDomain) {
                $Domain = $null
            }
        }
        if ($null -ne $Domain) { $Domain }
    }
    $DKIM = foreach ($DkimConfig in ($BatchResults | Where-Object { $_.Domain } | Select-Object Domain, Enabled, Status)) {
        $Domain = $DkimConfig
        foreach ($ExclusionDomain in $ExclusionDomains) {
            if ($Domain.Domain -like $ExclusionDomain) {
                $Domain = $null
            }
        }
        if ($null -ne $Domain) { $Domain }
    }

    # List of domains for each way to enable DKIM
    $NewDomains = $AllDomains | Where-Object { $DKIM.Domain -notcontains $_ }
    $SetDomains = $DKIM | Where-Object { $AllDomains -contains $_.Domain -and $_.Enabled -eq $false }

    $MissingDKIM = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $NewDomains) {
        $MissingDKIM.AddRange($NewDomains)
    }
    if ($null -ne $SetDomains) {
        $MissingDKIM.AddRange($SetDomains.Domain)
    }

    $CurrentValue = if ($MissingDKIM.Count -eq 0) { [PSCustomObject]@{'state' = 'Configured correctly' } } else { [PSCustomObject]@{'MissingDKIM' = $MissingDKIM } }
    $ExpectedValue = [PSCustomObject]@{'state' = 'Configured correctly' }

    if ($Settings.remediate -eq $true) {

        if ($null -eq $NewDomains -and $null -eq $SetDomains) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'DKIM is already enabled for all available domains.' -sev Info
        } else {
            $ErrorCounter = 0
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Trying to enable DKIM for:$($NewDomains -join ', ' ) $($SetDomains.Domain -join ', ')" -sev Info

            # New-domains
            $Request = foreach ($Domain in $NewDomains) {
                @{
                    CmdletInput = @{
                        CmdletName = 'New-DkimSigningConfig'
                        Parameters = @{ KeySize = 2048; DomainName = $Domain; Enabled = $true }
                    }
                }
            }
            if ($null -ne $Request) { $BatchResults = New-ExoBulkRequest -tenantid $Tenant -cmdletArray @($Request) -useSystemMailbox $true }
            foreach ($Result in $BatchResults) {
                if ($Result.error) {
                    $ErrorCounter ++
                    $ErrorMessage = Get-NormalizedError -Message $Result.error
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable DKIM. Error: $ErrorMessage" -sev Error
                }
            }

            # Set-domains
            $Request = foreach ($Domain in $SetDomains) {
                @{
                    CmdletInput = @{
                        CmdletName = 'Set-DkimSigningConfig'
                        Parameters = @{ Identity = $Domain.Domain; Enabled = $true }
                    }
                }
            }
            if ($null -ne $Request) { $BatchResults = New-ExoBulkRequest -tenantid $Tenant -cmdletArray @($Request) -useSystemMailbox $true }
            foreach ($Result in $BatchResults) {
                if ($Result.error) {
                    $ErrorCounter ++
                    $ErrorMessage = Get-NormalizedError -Message $Result.error
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set DKIM. Error: $ErrorMessage" -sev Error
                }
            }

            if ($ErrorCounter -eq 0) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Enabled DKIM for all domains in tenant' -sev Info
            } elseif ($ErrorCounter -gt 0 -and $ErrorCounter -lt ($NewDomains.Count + $SetDomains.Count)) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Failed to enable DKIM for some domains in tenant' -sev Error
            } else {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Failed to enable DKIM for all domains in tenant' -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($null -eq $NewDomains -and $null -eq $SetDomains) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DKIM is enabled for all available domains' -sev Info
        } else {
            $NoDKIM = ($NewDomains + $SetDomains.Domain) -join ';'
            Write-StandardsAlert -message "DKIM is not enabled for: $NoDKIM" -object @{NewDomains = $NewDomains; SetDomains = $SetDomains } -tenant $tenant -standardName 'AddDKIM' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "DKIM is not enabled for: $NoDKIM" -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $DKIMState = if ($null -eq $NewDomains -and $null -eq $SetDomains) { $true } else { $SetDomains, $NewDomains }
        Set-CIPPStandardsCompareField -FieldName 'standards.AddDKIM' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $tenant
        Add-CIPPBPAField -FieldName 'DKIM' -FieldValue $DKIMState -StoreAs bool -Tenant $tenant
    }
}
