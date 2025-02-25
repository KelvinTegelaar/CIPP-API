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

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $GroupType = $Request.Query.GroupType ?? $Request.Body.GroupType
    $OnlyAllowInternal = $Request.Query.OnlyAllowInternal ?? $Request.Body.OnlyAllowInternal
    $ID = $Request.Query.ID ?? $Request.Body.ID

    Try {
        $Result = Set-CIPPGroupAuthentication -ID $ID -GroupType $GroupType -OnlyAllowInternalString $OnlyAllowInternal -tenantFilter $TenantFilter -APIName $APIName -Headers $Headers
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "$($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })

}
