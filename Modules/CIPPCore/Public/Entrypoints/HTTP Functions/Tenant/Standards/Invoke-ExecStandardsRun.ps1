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
    try {
        $null = Invoke-CIPPStandardsRun -Tenantfilter $tenantfilter -Force
        $Results = "Successfully Started Standards Run for Tenant $tenantfilter"
    } catch {
        $Results = "Failed to start standards run for $tenantfilter. Error: $($_.Exception.Message)"
    }

    $Results = [pscustomobject]@{'Results' = "$results" }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
