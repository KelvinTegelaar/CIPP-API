param($tenant)

try {
    $Request = New-ExoRequest -tenantid $Tenant -cmdlet "Set-TransportConfig" -cmdParams @{ SmtpClientAuthenticationDisabled = $true }
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Disabled SMTP Basic Authentication" -sev Info
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to disable SMTP Basic Authentication: $($_.exception.message)" -sev Error
}