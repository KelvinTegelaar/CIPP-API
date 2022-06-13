using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
$Table = Get-CIPPTable -TableName ExcludedLicenses
try {
    if ($Request.Query.List) {
        $Rows = Get-AzTableRow -Table $table
        if ($Rows.Count -lt 1) {
            $TableBaseData = '[{"GUID":"16ddbbfc-09ea-4de2-b1d7-312db6112d70","Product_Display_Name":"MICROSOFT TEAMS (FREE)"},{"GUID":"1f2f344a-700d-42c9-9427-5cea1d5d7ba6","Product_Display_Name":"MICROSOFT STREAM"},{"GUID":"338148b6-1b11-4102-afb9-f92b6cdc0f8d","Product_Display_Name":"DYNAMICS 365 P1 TRIAL FOR INFORMATION WORKERS"},{"GUID":"606b54a9-78d8-4298-ad8b-df6ef4481c80","Product_Display_Name":"Power Virtual Agents Viral Trial"},{"GUID":"61e6bd70-fbdb-4deb-82ea-912842f39431","Product_Display_Name":"Dynamics 365 Customer Service Insights Trial"},{"GUID":"6470687e-a428-4b7a-bef2-8a291ad947c9","Product_Display_Name":"WINDOWS STORE FOR BUSINESS"},{"GUID":"710779e8-3d4a-4c88-adb9-386c958d1fdf","Product_Display_Name":"MICROSOFT TEAMS EXPLORATORY"},{"GUID":"74fbf1bb-47c6-4796-9623-77dc7371723b","Product_Display_Name":"Microsoft Teams Trial"},{"GUID":"90d8b3f8-712e-4f7b-aa1e-62e7ae6cbe96","Product_Display_Name":"Business Apps (free)"},{"GUID":"a403ebcc-fae0-4ca2-8c8c-7a907fd6c235","Product_Display_Name":"Power BI (free)"},{"GUID":"bc946dac-7877-4271-b2f7-99d2db13cd2c","Product_Display_Name":"Dynamics 365 Customer Voice Trial"},{"GUID":"dcb1a3ae-b33f-4487-846a-a640262fadf4","Product_Display_Name":"Microsoft Power Apps Plan 2 Trial"},{"GUID":"f30db892-07e9-47e9-837c-80727f46fd3d","Product_Display_Name":"MICROSOFT FLOW FREE"},{"GUID":"fcecd1f9-a91e-488d-a918-a96cdb6ce2b0","Product_Display_Name":"Microsoft Dynamics AX7 User Trial"}]' | ConvertFrom-Json -AsHashtable -depth 10
            foreach ($Row in $TableBaseData) {
                $TableRow = @{
                    table        = $Table
                    partitionKey = 'License'
                    rowKey       = $row.GUID
                    property     = $Row
                }
                Add-AzTableRow @TableRow | Out-Null
                $Rows = Get-AzTableRow -Table $table
            }
        }
        Log-Request -API $APINAME -user $request.headers.'x-ms-client-principal'  -message "got excluded tenants list" -Sev "Info"
        $body = @($Rows)
    }

    # Interact with query parameters or the body of the request.
    $name = $Request.Query.TenantFilter
    if ($Request.Query.AddExclusion) {
        $AddObject = @{
            "GUID"                 = $Request.body.GUID
            "Product_Display_Name" = $request.body.SKUName
        }
        $TableRow = @{
            table        = $Table
            partitionKey = 'License'
            rowKey       = $Request.body.GUID
            property     = $AddObject
        }
        Add-AzTableRow @TableRow | Out-Null
        Log-Request -API $APINAME -tenant $($name) -user $request.headers.'x-ms-client-principal'   -message "Added exclusion for customer $($name)" -Sev "Info" 
        $body = [pscustomobject]@{"Results" = "Success. We've added $($request.body.SKUName) to the excluded list." }
    }

    if ($Request.Query.RemoveExclusion) {
        Remove-AzTableRow -Table $Table -RowKey $Request.Query.GUID -PartitionKey 'license'
        Log-Request -API $APINAME -tenant $($name) -user $request.headers.'x-ms-client-principal'   -message "Removed exclusion for customer $($name)" -Sev "Info"
        $body = [pscustomobject]@{"Results" = "Success. We've removed $($Request.query.guid) from the excluded list." }
    }


}
catch {
    Log-Request -API $APINAME -tenant $($name) -user $request.headers.'x-ms-client-principal'   -message "Exclusion API failed. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Failed. $($_.Exception.Message)" }
}



# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
