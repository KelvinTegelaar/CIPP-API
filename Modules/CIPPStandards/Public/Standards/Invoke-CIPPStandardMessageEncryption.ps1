function Invoke-CIPPStandardMessageEncryption {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) MessageEncryption
    .SYNOPSIS
        (Label) Enable Purview Message Encryption
    .DESCRIPTION
        (Helptext) Enables Microsoft Purview Message Encryption by turning on Azure RMS licensing for Exchange Online. Skipped with a warning when the tenant still points at an on-premises AD RMS cluster, because AD RMS has to be migrated to Azure RMS first. This standard only turns the feature on: branding, one-time passcodes, and social ID sign-in for encrypted messages are configured in the [Configure Encrypted Message Branding (OME)](https://standards.cipp.app/standards/omebranding) standard. [Read more](https://learn.microsoft.com/en-us/purview/set-up-new-message-encryption-capabilities)
        (DocsDescription) Sets AzureRMSLicensingEnabled to true, the only prerequisite for Microsoft Purview Message Encryption. Reports the IRM licensing state per tenant, including the licensing location, so you can see at a glance which tenants have message encryption available. Remediation is deliberately skipped for tenants with an on-premises AD RMS licensing location, as Purview Message Encryption is not compatible with AD RMS and those tenants need to be migrated to Azure RMS first.
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Turns on the built-in encryption that lets staff send protected email to anyone, including recipients outside the organization. Uses licensing the organization already owns, removing the need for a separate secure-email product.
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2026-08-04
        POWERSHELLEQUIVALENT
            Set-IRMConfiguration -AzureRMSLicensingEnabled \$true
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
    $TestResult = Test-CIPPStandardLicense -StandardName 'MessageEncryption' -TenantFilter $Tenant -Preset Exchange

    if ($TestResult -eq $false) {
        return $true
    }

    try {
        $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-IRMConfiguration' | Select-Object -First 1
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the IRM configuration for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }

    # Purview Message Encryption is not compatible with on-premises AD RMS. A licensing location that
    # is not an Azure RMS URL means the tenant still points at an AD RMS cluster and has to be
    # migrated before message encryption can be enabled.
    # ponytail: URL-shape heuristic, the only signal Get-IRMConfiguration gives us. Get-AipServiceConfiguration would confirm it, but that needs the AIPService module which CIPP does not ship.
    $LicensingLocation = @($CurrentState.LicensingLocation | Where-Object { $_ })
    $AdRmsDetected = @($LicensingLocation | Where-Object { $_ -notmatch 'aadrm\.|azurerms|\.microsoft\.(com|us)' }).Count -gt 0
    $StateIsCorrect = $CurrentState.AzureRMSLicensingEnabled -eq $true -and $AdRmsDetected -eq $false

    if ($Settings.remediate -eq $true) {
        if ($AdRmsDetected) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "An on-premises AD RMS licensing location was found ($($LicensingLocation -join ', ')). Migrate to Azure RMS before enabling Purview Message Encryption. Skipping remediation." -sev Warning
        } elseif ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Purview Message Encryption is already enabled.' -sev Info
        } else {
            try {
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-IRMConfiguration' -cmdParams @{ AzureRMSLicensingEnabled = $true }
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Enabled Purview Message Encryption.' -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable Purview Message Encryption. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Purview Message Encryption is enabled.' -sev Info
        } else {
            $Message = if ($AdRmsDetected) {
                'Purview Message Encryption cannot be used, the tenant still uses an on-premises AD RMS licensing location.'
            } else {
                'Purview Message Encryption is not enabled.'
            }
            $Object = [PSCustomObject]@{
                AzureRMSLicensingEnabled = $CurrentState.AzureRMSLicensingEnabled
                LicensingLocation        = $LicensingLocation
                AdRmsDetected            = $AdRmsDetected
            }
            Write-StandardsAlert -message $Message -object $Object -tenant $Tenant -standardName 'MessageEncryption' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message $Message -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $ReportCurrent = [PSCustomObject]@{
            AzureRMSLicensingEnabled = $CurrentState.AzureRMSLicensingEnabled
            LicensingLocation        = $LicensingLocation
            AdRmsDetected            = $AdRmsDetected
        }
        $ReportExpected = [PSCustomObject]@{
            AzureRMSLicensingEnabled = $true
            LicensingLocation        = $LicensingLocation
            AdRmsDetected            = $false
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.MessageEncryption' -CurrentValue $ReportCurrent -ExpectedValue $ReportExpected -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'messageEncryptionEnabled' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
