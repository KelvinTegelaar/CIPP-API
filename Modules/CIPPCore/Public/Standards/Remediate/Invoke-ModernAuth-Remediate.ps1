function Invoke-ModernAuth-Remediate {
        <#
    .FUNCTIONALITY
    Internal
    #>
        param($Tenant, $Settings)

        Write-LogMessage -API 'Standards' -tenant $tenant -message 'Modern Authentication is enabled by default. This standard is no longer required.' -sev Info
}
