function Invoke-CIPPStandardLegacyMFACleanup {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    Write-LogMessage -API 'Standards' -tenant $tenant -message 'Per User MFA APIs have been disabled.' -sev Info

}
