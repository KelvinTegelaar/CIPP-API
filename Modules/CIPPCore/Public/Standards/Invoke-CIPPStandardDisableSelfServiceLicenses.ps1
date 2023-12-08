function Invoke-DisableSelfServiceLicenses {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.Remediate) {
        

    try {
        Write-LogMessage "Standards API: $($Tenant, $Settings) failed to disable License Buy Self Service: $($exception.message)" -sev Error

    } catch {
        Write-LogMessage "Standards API: $($Tenant, $Settings) failed to disable License Buy Self Service: $($exception.message)" -sev Error
    }
}
}
