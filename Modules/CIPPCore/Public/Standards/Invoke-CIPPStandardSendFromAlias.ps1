function Invoke-CIPPStandardSendFromAlias {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SendFromAlias
    .SYNOPSIS
        (Label) Set Send from alias state
    .DESCRIPTION
        (Helptext) Enables or disables the ability for users to send from their alias addresses.
        (DocsDescription) Allows users to change the 'from' address to any set in their Azure AD Profile.
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Allows employees to send emails from their alternative email addresses (aliases) rather than just their primary address. This is useful for employees who manage multiple roles or departments, enabling them to send emails from the most appropriate address for the context.
        ADDEDCOMPONENT
    {"type":"autoComplete","multiple":false,"creatable":false,"label":"Select value","name":"standards.SendFromAlias.state","options":[{"label":"Enabled","value":"true"},{"label":"Disabled","value":"false"}]}
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
        return $true
    } #we're done.

    try {
        $CurrentInfo = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').SendFromAliasEnabled
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the SendFromAlias state for $Tenant. Error:  $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }

    # Backwards compat: existing configs have no state (null) → default to 'true' (original behavior). For pre v10.1
    $state = $Settings.state.value ?? $Settings.state ?? 'true'
    $WantedState = [System.Convert]::ToBoolean($state)

    if ($Settings.remediate -eq $true) {
        if ($CurrentInfo -ne $WantedState) {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ SendFromAliasEnabled = $WantedState }
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Send from alias set to $state." -sev Info
                $CurrentInfo = $WantedState
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set send from alias to $state. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Send from alias is already set to $state." -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($CurrentInfo -eq $WantedState) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Send from alias is set to $state." -sev Info
        } else {
            Write-StandardsAlert -message "Send from alias is not set to $state" -object $CurrentInfo -tenant $Tenant -standardName 'SendFromAlias' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Send from alias is not set to $state." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'SendFromAlias' -FieldValue $CurrentInfo -StoreAs bool -Tenant $Tenant
        $CurrentValue = @{ SendFromAliasEnabled = $CurrentInfo }
        $ExpectedValue = @{ SendFromAliasEnabled = $WantedState }
        Set-CIPPStandardsCompareField -FieldName 'standards.SendFromAlias' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}
