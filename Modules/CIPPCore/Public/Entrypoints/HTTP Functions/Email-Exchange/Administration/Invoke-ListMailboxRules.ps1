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

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter

    $Table = Get-CIPPTable -TableName cachembxrules
    if ($TenantFilter -ne 'AllTenants') {
        $Table.Filter = "Tenant eq '$TenantFilter'"
    }
    $Rows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).Addhours(-1)

    $Metadata = @{}
    if (!$Rows -or ($TenantFilter -eq 'AllTenants' -and ($Rows | Measure-Object).Count -eq 1)) {
        $Metadata = [PSCustomObject]@{
            QueueMessage = 'Loading data. Please check back in 1 minute'
        }
        $GraphRequest = @()

        if ($TenantFilter -eq 'AllTenants') {
            $Tenants = Get-Tenants -IncludeErrors | Select-Object defaultDomainName
            $Type = 'All Tenants'
        } else {
            $Tenants = @(@{ defaultDomainName = $TenantFilter })
            $Type = $TenantFilter
        }
        $Queue = New-CippQueueEntry -Name "Mailbox Rules ($Type)" -TotalTasks ($Tenants | Measure-Object).Count
        $Batch = $Tenants | Select-Object defaultDomainName, @{Name = 'FunctionName'; Expression = { 'ListMailboxRulesQueue' } }, @{Name = 'QueueName'; Expression = { $_.defaultDomainName } }, @{Name = 'QueueId'; Expression = { $Queue.RowKey } }
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
            $NewObj = $_.Rules | ConvertFrom-Json -ErrorAction SilentlyContinue
            $NewObj | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $_.Tenant -Force
            $NewObj
        }
    }

    $Body = @{
        Results  = @($GraphRequest)
        Metadata = $Metadata
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
