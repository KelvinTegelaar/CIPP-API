using namespace System.Net

Function Invoke-ExecStandardsRun {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $tenantfilter = if ($Request.Query.TenantFilter) { $Request.Query.TenantFilter } else { 'allTenants' }
    $TemplateId = if ($Request.Query.TemplateId) { $Request.Query.TemplateId } else { '*' }
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'StandardsTemplateV2'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter | Sort-Object TimeStamp).JSON | ConvertFrom-Json | Where-Object {
        $_.guid -like $TemplateId
    }



    $ConfigTable = Get-CIPPTable -tablename Config
    $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'OffloadFunctions' and RowKey eq 'OffloadFunctions'"

    if ($Config -and $Config.state -eq $true) {
        if ($env:CIPP_PROCESSOR -ne 'true') {

            $ProcessorFunction = [PSCustomObject]@{
                PartitionKey = 'Function'
                RowKey       = "Invoke-CIPPStandardsRun-$tenantfilter"
                FunctionName = 'Invoke-CIPPStandardsRun'
                Parameters   = [string](ConvertTo-Json -Compress -InputObject @{
                        TenantFilter = $tenantfilter
                        TemplateId   = $TemplateId
                        runManually  = [bool]$Templates.runManually
                        Force        = $true
                    })
            }
            $ProcessorQueue = Get-CIPPTable -TableName 'ProcessorQueue'
            Add-AzDataTableEntity @ProcessorQueue -Entity $ProcessorFunction -Force
            $Results = "Successfully Queued Standards Run for Tenant $tenantfilter"
        }
    } else {
        try {
            $null = Invoke-CIPPStandardsRun -Tenantfilter $tenantfilter -TemplateID $TemplateId -runManually ([bool]$Templates.runManually) -Force
            $Results = "Successfully Started Standards Run for Tenant $tenantfilter"
            Write-LogMessage -tenant $tenantfilter -API $APINAME -message $Results -Sev 'Info'
        } catch {
            $Results = "Failed to start standards run for $tenantfilter. Error: $($_.Exception.Message)"
            Write-LogMessage -tenant $tenantfilter -API $APINAME -message $Results -Sev 'Error'
        }
    }

    $Results = [pscustomobject]@{'Results' = "$results" }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
