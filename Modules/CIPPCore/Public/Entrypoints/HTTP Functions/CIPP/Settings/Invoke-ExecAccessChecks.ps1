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

    switch ($Request.Query.Type) {
        'Permissions' {
            if (!$Request.Query.SkipCache) {
                $Results = (Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq 'AccessPermissions'").Data | ConvertFrom-Json
                if (!$Results) {
                    $Results = Test-CIPPAccessPermissions -tenantfilter $ENV:TenantID -APIName $APINAME -ExecutingUser $Request.Headers.'x-ms-client-principal'
                }
            } else {
                $Results = Test-CIPPAccessPermissions -tenantfilter $ENV:TenantID -APIName $APINAME -ExecutingUser $Request.Headers.'x-ms-client-principal'
            }
        }
        'Tenants' {
            $Results = Test-CIPPAccessTenant -TenantCSV $Request.Body.tenantid -ExecutingUser $Request.Headers.'x-ms-client-principal'
        }
        'GDAP' {
            if (!$Request.Query.SkipCache) {
                $Results = (Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq 'GDAPRelationships'").Data | ConvertFrom-Json
                if (!$Results) {
                    $Results = Test-CIPPGDAPRelationships
                }
            } else {
                $Results = Test-CIPPGDAPRelationships
            }
        }
    }

    $body = [pscustomobject]@{'Results' = $Results }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
