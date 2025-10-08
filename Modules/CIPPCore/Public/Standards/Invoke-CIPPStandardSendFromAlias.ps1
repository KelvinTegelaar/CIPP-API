function Invoke-CIPPStandardSendFromAlias {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SendFromAlias
    .SYNOPSIS
        (Label) Allow users to send from their alias addresses
    .DESCRIPTION
        (Helptext) Enables the ability for users to send from their alias addresses.
        (DocsDescription) Allows users to change the 'from' address to any set in their Azure AD Profile.
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Allows employees to send emails from their alternative email addresses (aliases) rather than just their primary address. This is useful for employees who manage multiple roles or departments, enabling them to send emails from the most appropriate address for the context.
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        ADDEDDATE
            2022-05-25
        POWERSHELLEQUIVALENT
            Set-Mailbox
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'SendFromAlias' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    try {
        $CurrentInfo = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').SendFromAliasEnabled
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the SendFromAlias state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        if ($CurrentInfo -ne $true) {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ SendFromAliasEnabled = $true }
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Send from alias enabled.' -sev Info
                $CurrentInfo = $true
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable send from alias. Error: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Send from alias is already enabled.' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($CurrentInfo -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Send from alias is enabled.' -sev Info
        } else {
            Write-StandardsAlert -message 'Send from alias is not enabled' -object $CurrentInfo -tenant $tenant -standardName 'SendFromAlias' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Send from alias is not enabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'SendFromAlias' -FieldValue $CurrentInfo -StoreAs bool -Tenant $tenant
        Set-CIPPStandardsCompareField -FieldName 'standards.SendFromAlias' -FieldValue $CurrentInfo -Tenant $tenant
    }
}
