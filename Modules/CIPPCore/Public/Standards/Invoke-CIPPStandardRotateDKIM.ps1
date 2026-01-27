function Invoke-CIPPStandardRotateDKIM {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) RotateDKIM
    .SYNOPSIS
        (Label) Rotate DKIM keys that are 1024 bit to 2048 bit
    .DESCRIPTION
        (Helptext) Rotate DKIM keys that are 1024 bit to 2048 bit
        (DocsDescription) Rotate DKIM keys that are 1024 bit to 2048 bit
    .NOTES
        CAT
            Exchange Standards
        TAG
            "CIS M365 5.0 (2.1.9)"
        EXECUTIVETEXT
            Upgrades email security by replacing older 1024-bit encryption keys with stronger 2048-bit keys for email authentication. This improves the organization's email security posture and helps prevent email spoofing and tampering, maintaining trust with email recipients.
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2023-03-14
        POWERSHELLEQUIVALENT
            Rotate-DkimSigningConfig
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'RotateDKIM' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    try {
        $DKIM = (New-ExoRequest -tenantid $tenant -cmdlet 'Get-DkimSigningConfig') | Where-Object { $_.Selector1KeySize -eq 1024 -and $_.Enabled -eq $true }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DKIM state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($Settings.remediate -eq $true) {

        if ($DKIM) {
            $DKIM | ForEach-Object {
                try {
                    (New-ExoRequest -tenantid $tenant -cmdlet 'Rotate-DkimSigningConfig' -cmdParams @{ KeySize = 2048; Identity = $_.Identity } -useSystemMailbox $true)
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Rotated DKIM for $($_.Identity)" -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to rotate DKIM Error: $ErrorMessage" -sev Error
                }
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DKIM is already rotated for all domains' -sev Info
        }

    }

    if ($Settings.alert -eq $true) {
        if ($DKIM) {
            Write-StandardsAlert -message "DKIM is not rotated for $($DKIM.Identity -join ';')" -object $DKIM -tenant $tenant -standardName 'RotateDKIM' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "DKIM is not rotated for $($DKIM.Identity -join ';')" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DKIM is rotated for all domains' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'DKIM' -FieldValue $DKIM -StoreAs json -Tenant $tenant

        $CurrentValue = @{
            domainsWith1024BitDKIM = @(@($DKIM.Identity) | Where-Object { $_ })
        }
        $ExpectedValue = @{
            domainsWith1024BitDKIM = @()
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.RotateDKIM' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $tenant
    }
}
