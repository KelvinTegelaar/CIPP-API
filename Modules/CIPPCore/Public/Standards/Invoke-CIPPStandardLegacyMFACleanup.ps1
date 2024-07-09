function Invoke-CIPPStandardLegacyMFACleanup {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    LegacyMFACleanup
    .CAT
    Entra (AAD) Standards
    .TAG
    "mediumimpact"
    .HELPTEXT
    This standard currently does not function and can be safely disabled
    .ADDEDCOMPONENT
    .LABEL
    Remove Legacy MFA if SD or CA is active
    .IMPACT
    Medium Impact
    .POWERSHELLEQUIVALENT
    Set-MsolUser -StrongAuthenticationRequirements $null
    .RECOMMENDEDBY
    .DOCSDESCRIPTION
    This standard currently does not function and can be safely disabled
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>




    param($Tenant, $Settings)
    Write-LogMessage -API 'Standards' -tenant $tenant -message 'Per User MFA APIs have been disabled.' -sev Info

}




