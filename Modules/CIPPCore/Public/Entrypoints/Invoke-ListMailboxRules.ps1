using namespace System.Net

Function Invoke-ListMailboxRules {
    <#
    .FUNCTIONALITY
    Entrypoint
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

    if (!$Rows) {
        #Push-OutputBinding -Name mbxrulequeue -Value $TenantFilter
        $GraphRequest = [PSCustomObject]@{
            Tenant   = 'Loading data. Please check back in 1 minute'
            Licenses = 'Loading data. Please check back in 1 minute'
        }
        $Batch = if ($TenantFilter -eq 'AllTenants') {
            Get-Tenants -IncludeErrors | ForEach-Object { $_ | Add-Member -NotePropertyName FunctionName -NotePropertyValue 'ListMailboxRulesQueue'; $_ }
        } else {
            [PSCustomObject]@{
                defaultDomainName = $TenantFilter
                FunctionName      = 'ListMailboxRulesQueue'
            }
        }
        if (($Batch | Measure-Object).Count -gt 0) {
            $InputObject = [PSCustomObject]@{
                OrchestratorName = 'ListMailboxRulesOrchestrator'
                Batch            = @($Batch)
                SkipLog          = $true
            }
            #Write-Host ($InputObject | ConvertTo-Json)
            $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5)
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
