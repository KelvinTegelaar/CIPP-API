using namespace System.Net

Function Invoke-ListTenantAllowBlockList {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $ListTypes = 'Sender','Url','FileHash'
    try {
        $Request = ForEach ($_ in $ListTypes) {
            @{
                CmdletInput = @{
                    CmdletName = 'Get-TenantAllowBlockListItems'
                    Parameters = @{ListType = $_ }
                }
            }
        }
        $BatchResults = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray $Request

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $BatchResults = $ErrorMessage
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($BatchResults)
        })
}
