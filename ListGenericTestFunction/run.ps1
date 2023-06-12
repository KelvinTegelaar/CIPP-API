using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


try {
    Write-LogMessage -API "Scheduler_Billing" -tenant "none" -message "Starting billing processing." -sev Info

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = (Get-AzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10
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

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @("Executed")
    }) -clobber