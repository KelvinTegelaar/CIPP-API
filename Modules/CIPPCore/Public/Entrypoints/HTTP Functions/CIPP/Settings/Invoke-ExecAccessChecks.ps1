using namespace System.Net

Function Invoke-ExecAccessChecks {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Table = Get-CIPPTable -tablename 'AccessChecks'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    if ($Request.Query.Permissions -eq 'true') {
        if ($Request.Query.Cached -eq 'true') {
            $Data = (Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq 'AccessPermissions'").Data | ConvertFrom-Json
            $Results = $Data
        } else {
            $Results = Test-CIPPAccessPermissions -tenantfilter $ENV:TenantID -APIName $APINAME -ExecutingUser $Request.Headers.'x-ms-client-principal'
        }
    }

    if ($Request.Query.Tenants -eq 'true') {
        $Results = Test-CIPPAccessTenant -TenantCSV $Request.Body.tenantid -ExecutingUser $Request.Headers.'x-ms-client-principal'
    }
    if ($Request.Query.GDAP -eq 'true') {
        if ($Request.Query.Cached -eq 'true') {
            $Data = (Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq 'GDAPRelationships'").Data | ConvertFrom-Json
            $Results = $Data
        } else {
            $Results = Test-CIPPGDAPRelationships
        }
    }

    $body = [pscustomobject]@{'Results' = $Results }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
