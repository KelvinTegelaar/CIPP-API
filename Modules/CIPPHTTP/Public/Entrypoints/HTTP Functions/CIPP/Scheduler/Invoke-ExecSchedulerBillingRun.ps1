Function Invoke-ExecSchedulerBillingRun {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Scheduler.Billing.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers


    try {
        Write-LogMessage -API 'Scheduler_Billing' -tenant 'none' -message 'Starting billing processing.' -sev Info

        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10
        foreach ($ConfigItem in $Configuration.PSObject.Properties.Name) {
            switch ($ConfigItem) {
                'Gradient' {
                    If ($Configuration.Gradient.enabled -and $Configuration.Gradient.BillingEnabled) {
                        New-GradientServiceSyncRun
                    }
                }
            }
        }
    } catch {
        Write-LogMessage -API 'Scheduler_Billing' -tenant 'none' -message "Could not start billing processing $($_.Exception.Message)" -sev Error -headers $Headers
    }

}
