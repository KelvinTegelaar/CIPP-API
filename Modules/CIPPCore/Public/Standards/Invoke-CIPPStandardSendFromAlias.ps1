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
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/exchange-standards#medium-impact
    #>

    param($Tenant, $Settings)

    $CurrentInfo = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').SendFromAliasEnabled

    if ($Settings.remediate -eq $true) {
        if ($CurrentInfo -eq $false) {
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
