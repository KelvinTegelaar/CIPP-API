using namespace System.Net

Function Invoke-ListOoO {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $Tenantfilter = $request.query.tenantFilter
    try {
        $Body = Get-CIPPOutOfOffice -userid $Request.query.userid -tenantFilter $TenantFilter -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal'
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $Body = [pscustomobject]@{'Results' = "Failed. $ErrorMessage" }

    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
