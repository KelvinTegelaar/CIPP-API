function Invoke-CIPPStandardLegacyMFACleanup {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) LegacyMFACleanup
    .SYNOPSIS
        (Label) Remove Legacy MFA if SD or CA is active
    .DESCRIPTION
        (Helptext) This standard currently does not function and can be safely disabled
        (DocsDescription) This standard currently does not function and can be safely disabled
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "mediumimpact"
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        POWERSHELLEQUIVALENT
            Set-MsolUser -StrongAuthenticationRequirements \$null
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/entra-aad-standards#medium-impact
    #>

    param($Tenant, $Settings)
    Write-LogMessage -API 'Standards' -tenant $tenant -message 'Per User MFA APIs have been disabled.' -sev Info

}
