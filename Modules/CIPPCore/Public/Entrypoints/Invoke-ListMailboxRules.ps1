using namespace System.Net

Function Invoke-ListMailboxRules {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter

    $Table = Get-CIPPTable -TableName cachembxrules
    if ($TenantFilter -ne 'AllTenants') {
        $Table.Filter = "Tenant eq '$TenantFilter'"
    }
    $Rows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).Addhours(-1)

    if (!$Rows -or ($TenantFilter -eq 'AllTenants' -and ($Rows | Measure-Object).Count -eq 1)) {
        $GraphRequest = [PSCustomObject]@{
            Tenant   = 'Loading data. Please check back in 1 minute'
            Licenses = 'Loading data. Please check back in 1 minute'
        }

        if ($TenantFilter -eq 'AllTenants') {
            $Tenants = Get-Tenants -IncludeErrors | Select-Object defaultDomainName
            $Type = 'All Tenants'
        } else {
            $Tenants = @(@{ defaultDomainName = $TenantFilter })
            $Type = $TenantFilter
        }
        $Queue = New-CippQueueEntry -Name "Mailbox Rules ($Type)" -TotalTasks ($Tenants | Measure-Object).Count
        $Batch = $Tenants | Select-Object defaultDomainName, @{Name = 'FunctionName'; Expression = { 'ListMailboxRulesQueue' } }, @{Name = 'QueueName'; Expression = { $_.defaultDomainName } }, @{Name = 'QueueId'; Expression = { $Queue.RowKey } }, @{Name = 'QueueName'; Expression = { $_.defaultDomainName } }

        if (($Batch | Measure-Object).Count -gt 0) {
            $InputObject = [PSCustomObject]@{
                OrchestratorName = 'ListMailboxRulesOrchestrator'
                Batch            = @($Batch)
                SkipLog          = $true
            }
            #Write-Host ($InputObject | ConvertTo-Json)
            $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
            Write-Host "Started permissions orchestration with ID = '$InstanceId'"
        }

    } else {
        if ($TenantFilter -ne 'AllTenants') {
            $Rows = $Rows | Where-Object -Property Tenant -EQ $TenantFilter
        }
        $GraphRequest = $Rows | ForEach-Object {
            $NewObj = $_.Rules | ConvertFrom-Json
            $NewObj | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $_.Tenant
            $NewObj
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}
