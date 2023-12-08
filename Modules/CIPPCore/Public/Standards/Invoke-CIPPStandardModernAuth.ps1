function Invoke-ModernAuth {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.Remediate) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'Modern Authentication is enabled by default. This standard is no longer required.' -sev Info
    }
}
