using namespace System.Net

function Invoke-ExecSchedulerBillingRun {
    <#
    .SYNOPSIS
    Execute scheduled billing processing for CIPP extensions
    
    .DESCRIPTION
    Processes scheduled billing operations for enabled CIPP extensions including Gradient and other billing-enabled services. Logs billing processing start, completion, and errors.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Scheduler.Billing.ReadWrite
        
    .NOTES
    Group: Scheduler
    Summary: Exec Scheduler Billing Run
    Description: Executes scheduled billing processing for enabled CIPP extensions, currently supporting Gradient service synchronization when billing is enabled. Logs all actions and errors.
    Tags: Scheduler,Billing,Extensions
    Response: No direct response - processes billing operations in the background
    Response: Actions performed:
    Response: - Processes Gradient billing if enabled and billing is enabled
    Response: - Logs billing processing start and completion
    Response: - Handles errors and logs them appropriately
    Example: The function processes billing operations and logs the results:
    Example: - Starts billing processing for enabled extensions
    Example: - Executes Gradient service sync runs if configured
    Example: - Logs success or failure of billing operations
    Error: Logs error details if billing processing fails.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        Write-LogMessage -API 'Scheduler_Billing' -tenant 'none' -message 'Starting billing processing.' -sev Info

        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10
        foreach ($ConfigItem in $Configuration.PSObject.Properties.Name) {
            switch ($ConfigItem) {
                'Gradient' {
                    if ($Configuration.Gradient.enabled -and $Configuration.Gradient.BillingEnabled) {
                        New-GradientServiceSyncRun
                    }
                }
            }
        }
    }
    catch {
        Write-LogMessage -API 'Scheduler_Billing' -tenant 'none' -message "Could not start billing processing $($_.Exception.Message)" -sev Error -headers $Headers
    }

}
