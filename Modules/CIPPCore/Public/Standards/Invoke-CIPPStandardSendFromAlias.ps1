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
            "mediumimpact"
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        POWERSHELLEQUIVALENT
            Set-Mailbox
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    $CurrentInfo = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').SendFromAliasEnabled

    If ($Settings.remediate -eq $true) {
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
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Send from alias is not enabled.' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'SendFromAlias' -FieldValue $CurrentInfo -StoreAs bool -Tenant $tenant
    }
}
