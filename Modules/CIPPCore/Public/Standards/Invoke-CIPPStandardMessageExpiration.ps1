function Invoke-CIPPStandardMessageExpiration {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) MessageExpiration
    .SYNOPSIS
        (Label) Lower Transport Message Expiration to 12 hours
    .DESCRIPTION
        (Helptext) Sets the transport message configuration to timeout a message at 12 hours.
        (DocsDescription) Expires messages in the transport queue after 12 hours. Makes the NDR for failed messages show up faster for users. Default is 24 hours.
    .NOTES
        CAT
            Exchange Standards
        TAG
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2024-02-23
        POWERSHELLEQUIVALENT
            Set-TransportConfig -MessageExpirationTimeout 12.00:00:00
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'MessageExpiration' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    try {
        $MessageExpiration = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-TransportConfig').messageExpiration
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the MessageExpiration state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'
        if ($MessageExpiration -ne '12:00:00') {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-TransportConfig' -cmdParams @{MessageExpiration = '12:00:00' }
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Set transport configuration message expiration to 12 hours' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set transport configuration message expiration to 12 hours. Error: $ErrorMessage" -sev Debug
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Transport configuration message expiration is already set to 12 hours' -sev Info
        }

    }
    if ($Settings.alert -eq $true) {
        if ($MessageExpiration -eq '12:00:00') {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Transport configuration message expiration is set to 12 hours' -sev Info
        } else {
            $Object = [PSCustomObject]@{ MessageExpiration = $MessageExpiration }
            Write-StandardsAlert -message 'Transport configuration message expiration is not set to 12 hours' -object $Object -tenant $tenant -standardName 'MessageExpiration' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Transport configuration message expiration is not set to 12 hours' -sev Info
        }
    }
    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            MessageExpiration = $MessageExpiration
        }
        $ExpectedValue = @{
            MessageExpiration = '12:00:00'
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.MessageExpiration' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'messageExpiration' -FieldValue $MessageExpiration -StoreAs bool -Tenant $tenant
    }
}
