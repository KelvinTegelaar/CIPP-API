function Push-ExecApplicationCopy($QueueItem, $TriggerMetadata) {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    try {
        $Queueitem = $QueueItem | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        Write-Host "$($Queueitem | ConvertTo-Json -Depth 10)"
        New-CIPPApplicationCopy -App $queueitem.AppId -Tenant $Queueitem.Tenant
    } catch {
        Write-LogMessage -message "Error adding application to tenant $($Queueitem.Tenant) - $($_.Exception.Message)" -tenant $Queueitem.Tenant -API 'Add Multitenant App' -sev Error
    }
}
