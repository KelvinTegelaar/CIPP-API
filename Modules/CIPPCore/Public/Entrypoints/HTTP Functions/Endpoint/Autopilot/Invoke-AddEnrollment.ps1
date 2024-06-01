using namespace System.Net

Function Invoke-AddEnrollment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Input bindings are passed in via param block.
    $Tenants = ($Request.body | Select-Object Select_*).psobject.properties.value
    $Profbod = $Request.body
    $results = foreach ($Tenant in $tenants) {
        Set-CIPPDefaultAPEnrollment -TenantFilter $Tenant -ShowProgress $Profbod.ShowProgress -BlockDevice $Profbod.blockDevice -AllowReset $Profbod.AllowReset -EnableLog $Profbod.EnableLog -ErrorMessage $Profbod.ErrorMessage -TimeOutInMinutes $Profbod.TimeOutInMinutes -AllowFail $Profbod.AllowFail -OBEEOnly $Profbod.OBEEOnly
    }

    $body = [pscustomobject]@{'Results' = $results }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
