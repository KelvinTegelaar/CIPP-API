using namespace System.Net

Function Invoke-ExecAddAlert {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)


    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API 'Alerts' -message $request.body.text -Sev $request.body.Severity
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = 'Successfully generated alert.'
        })

}
