function Push-ExecApplicationCopy {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)
    try {
        Write-Host "$($Item | ConvertTo-Json -Depth 10)"
        New-CIPPApplicationCopy -App $Item.AppId -Tenant $Item.Tenant
    } catch {
        Write-LogMessage -message "Error adding application to tenant $($Item.Tenant) - $($_.Exception.Message)" -tenant $Item.Tenant -API 'Add Multitenant App' -sev Error
    }
}
