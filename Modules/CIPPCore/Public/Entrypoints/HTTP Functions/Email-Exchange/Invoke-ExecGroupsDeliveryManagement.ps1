using namespace System.Net

Function Invoke-ExecGroupsDeliveryManagement {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Group.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'


    # Interact with query parameters or the body of the request.
    Try {
        $SetResults = Set-CIPPGroupAuthentication -ID $Request.query.id -GroupType $Request.query.GroupType -OnlyAllowInternalString $Request.query.OnlyAllowInternal -tenantFilter $Request.query.TenantFilter -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal'
        $Results = [pscustomobject]@{'Results' = $SetResults }
    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Delivery Management failed: $($_.Exception.Message)" -Sev 'Error'
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
