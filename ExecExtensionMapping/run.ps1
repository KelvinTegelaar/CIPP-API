using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'
$Table = Get-CIPPTable -TableName CippMapping
try {
    
    if ($Request.Query.List) {
        $Rows = Get-AzDataTableEntity @Table
        if ($Rows.Count -lt 1) {
            $TableBaseData = Get-tenants
            $TableRows = foreach ($Row in $TableBaseData) {
                $row = $row | Select-Object *, HaloPSAId, GradientId
                $row.HaloPSAId = ""
                $row.GradientId = ""
                Add-AzDataTableEntity @Table -Entity ([pscustomobject]$Row) -Force | Out-Null
            }
            
            $Rows = Get-AzDataTableEntity @Table

            Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message 'got tenant mapping list' -Sev 'Info'
        }
        $body = @($Rows | Select-Object displayName, defaultDomainName, HaloPSAId, GradientId)
    }

    # Interact with query parameters or the body of the request.
    $name = $Request.Query.TenantFilter
    if ($Request.Query.AddExclusion) {
        $AddObject = @{
            PartitionKey           = 'License'
            RowKey                 = $Request.body.GUID
            'GUID'                 = $Request.body.GUID
            'Product_Display_Name' = $request.body.SKUName
        }
        Add-AzDataTableEntity @Table -Entity $AddObject -Force

        Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message "Added exclusion $($request.body.SKUName)" -Sev 'Info' 
        $body = [pscustomobject]@{'Results' = "Success. We've added $($request.body.SKUName) to the excluded list." }
    }

    if ($Request.Query.RemoveExclusion) {
        $Filter = "RowKey eq '{0}' and PartitionKey eq 'License'" -f $Request.Query.Guid
        $Entity = Get-AzDataTableEntity @Table -Filter $Filter
        Remove-AzDataTableEntity @Table -Entity $Entity
        Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message "Removed exclusion $($Request.Query.GUID)" -Sev 'Info'
        $body = [pscustomobject]@{'Results' = "Success. We've removed $($Request.query.guid) from the excluded list." }
    }
}
catch {
    Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message "Exclusion API failed. $($_.Exception.Message)" -Sev 'Error'
    $body = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
