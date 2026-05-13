function Invoke-CIPPStandardModernAuth {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.remediate -eq $true) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'Modern Authentication is enabled by default. This standard is no longer required.' -sev Info
    }
}
