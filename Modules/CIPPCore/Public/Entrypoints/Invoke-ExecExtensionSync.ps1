using namespace System.Net

Function Invoke-ExecExtensionSync {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    if ($Request.Query.Extension -eq 'Gradient') {
        try {
            Write-LogMessage -API 'Scheduler_Billing' -tenant 'none' -message 'Starting billing processing.' -sev Info
            $Table = Get-CIPPTable -TableName Extensionsconfig
            $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10
            foreach ($ConfigItem in $Configuration.psobject.properties.name) {
                switch ($ConfigItem) {
                    'Gradient' {
                        If ($Configuration.Gradient.enabled -and $Configuration.Gradient.BillingEnabled) {
                            Push-OutputBinding -Name gradientqueue -Value 'LetsGo'
                            $Results = [pscustomobject]@{'Results' = 'Succesfully started Gradient Sync' }
                        }
                    }
                }
            }
        } catch {
            $Results = [pscustomobject]@{'Results' = "Could not start Gradient Sync: $($_.Exception.Message)" }

            Write-LogMessage -API 'Scheduler_Billing' -tenant 'none' -message "Could not start billing processing $($_.Exception.Message)" -sev Error
        }
    }

    if ($Request.Query.Extension -eq 'NinjaOne') {
        try {
            $Table = Get-CIPPTable -TableName NinjaOneSettings

            $CIPPMapping = Get-CIPPTable -TableName CippMapping
            $Filter = "PartitionKey eq 'NinjaOrgsMapping'"
            $TenantsToProcess = Get-AzDataTableEntity @CIPPMapping -Filter $Filter | Where-Object { $Null -ne $_.NinjaOne -and $_.NinjaOne -ne '' }

            foreach ($Tenant in $TenantsToProcess) {
                Push-OutputBinding -Name NinjaProcess -Value @{
                    'NinjaAction'  = 'SyncTenant'
                    'MappedTenant' = $Tenant
                }

            }

            $AddObject = @{
                PartitionKey   = 'NinjaConfig'
                RowKey         = 'NinjaLastRunTime'
                'SettingValue' = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK')
            }

            Add-AzDataTableEntity @Table -Entity $AddObject -Force

            Write-LogMessage -API 'NinjaOneAutoMap_Queue' -user 'CIPP' -message "NinjaOne Synchronization Queued for $(($TenantsToProcess | Measure-Object).count) Tenants" -Sev 'Info' 

            $Results = [pscustomobject]@{'Results' = "NinjaOne Synchronization Queued for $(($TenantsToProcess | Measure-Object).count) Tenants" }
        } catch {
            $Results = [pscustomobject]@{'Results' = "Could not start NinjaOne Sync: $($_.Exception.Message)" }
            Write-LogMessage -API 'Scheduler_Billing' -tenant 'none' -message "Could not start NinjaOne Sync $($_.Exception.Message)" -sev Error
        }

    }


    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        }) -clobber

}
