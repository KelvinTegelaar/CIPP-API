param($tenant)

try {
    Write-LogMessage "Standards API: $($tenant) failed to disable License Buy Self Service: $($exception.message)" -sev Error

}
catch {
    Write-LogMessage "Standards API: $($tenant) failed to disable License Buy Self Service: $($exception.message)" -sev Error
}