function Invoke-CIPPStandardDisableTNEF {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableTNEF
    .SYNOPSIS
        (Label) Disable TNEF/winmail.dat
    .DESCRIPTION
        (Helptext) Disables Transport Neutral Encapsulation Format (TNEF)/winmail.dat for the tenant. TNEF can cause issues if the recipient is not using a client supporting TNEF.
        (DocsDescription) Disables Transport Neutral Encapsulation Format (TNEF)/winmail.dat for the tenant. TNEF can cause issues if the recipient is not using a client supporting TNEF. Cannot be overridden by the user. For more information, see [Microsoft's documentation.](https://learn.microsoft.com/en-us/exchange/mail-flow/content-conversion/tnef-conversion?view=exchserver-2019)
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Prevents the creation of winmail.dat attachments that can cause compatibility issues when sending emails to external recipients using non-Outlook email clients. This improves email compatibility and reduces support issues with external partners and customers.
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2024-04-26
        POWERSHELLEQUIVALENT
            Set-RemoteDomain -Identity 'Default' -TNEFEnabled \$false
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param ($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'DisableTNEF' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    try {
        $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-RemoteDomain' -cmdParams @{Identity = 'Default' }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableTNEF state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        if ($CurrentState.TNEFEnabled -ne $false) {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-RemoteDomain' -cmdParams @{Identity = 'Default'; TNEFEnabled = $false } -useSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled TNEF for Default Remote Domain' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable TNEF for Default Remote Domain. Error: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'TNEF is already disabled for Default Remote Domain' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($CurrentState.TNEFEnabled -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'TNEF is disabled for Default Remote Domain' -sev Info
        } else {
            $Object = $CurrentState | Select-Object -Property TNEFEnabled
            Write-StandardsAlert -message 'TNEF is not disabled for Default Remote Domain' -object $Object -tenant $tenant -standardName 'DisableTNEF' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'TNEF is not disabled for Default Remote Domain' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $State = if ($CurrentState.TNEFEnabled -ne $false) { $false } else { $true }

        $CurrentValue = [PSCustomObject]@{
            DisableTNEF = $State
        }
        $ExpectedValue = [PSCustomObject]@{
            DisableTNEF = $true
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.DisableTNEF' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'TNEFDisabled' -FieldValue $State -StoreAs bool -Tenant $tenant
    }

}
