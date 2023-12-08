function Invoke-DisableBasicAuth {
        <#
    .FUNCTIONALITY
    Internal
    #>
        param($Tenant, $Settings)
    If ($Settings.Remediate) {
        
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Basic Authentication is disabled by default. SMTP authentication is still allowed. Please use the standard 'Disable SMTP Basic Authentication' to disable" -sev Info
}
}
