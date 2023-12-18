function Invoke-CIPPStandardLegacyMFA {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    Write-LogMessage -API 'Standards' -tenant $tenant -message 'Per user MFA APIs have been disabled.' -sev Info

}
