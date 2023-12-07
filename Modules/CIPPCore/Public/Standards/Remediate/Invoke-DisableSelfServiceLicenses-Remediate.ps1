function Invoke-DisableSelfServiceLicenses-Remediate {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    try {
        Write-LogMessage "Standards API: $($Tenant, $Settings) failed to disable License Buy Self Service: $($exception.message)" -sev Error

    } catch {
        Write-LogMessage "Standards API: $($Tenant, $Settings) failed to disable License Buy Self Service: $($exception.message)" -sev Error
    }
}
