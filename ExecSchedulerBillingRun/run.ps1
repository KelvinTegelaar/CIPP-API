# Input bindings are passed in via param block.
param($QueueItem)

# Get the current universal time in the default string format.
try {
    Write-LogMessage -API "Scheduler_Billing" -tenant "none" -message "Starting billing processing." -sev Info

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10
    foreach ($ConfigItem in $Configuration.psobject.properties.name) {
        switch ($ConfigItem) {
            "Gradient" {
                If ($Configuration.Gradient.enabled -and $Configuration.Gradient.BillingEnabled) {
                    New-GradientServiceSyncRun
                }
            }
        }
    }
}
catch {
    Write-LogMessage -API "Scheduler_Billing" -tenant "none" -message "Could not start billing processing $($_.Exception.Message)" -sev Error
}