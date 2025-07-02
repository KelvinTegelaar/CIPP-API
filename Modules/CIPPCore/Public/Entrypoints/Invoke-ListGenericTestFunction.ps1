using namespace System.Net

function Invoke-ListGenericTestFunction {
    <#
    .SYNOPSIS
    Generic test function for API endpoint validation
    
    .DESCRIPTION
    A simple test function that returns the base URL of the API endpoint for validation and testing purposes
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
        
    .NOTES
    Group: Testing
    Summary: List Generic Test Function
    Description: A simple test function that extracts and returns the base URL from the x-ms-original-url header for API endpoint validation and testing purposes
    Tags: Testing,Validation,API
    Response: Returns the base URL of the API endpoint
    Response: Example: "https://contoso.azurewebsites.net"
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $graphRequest = ($Headers.'x-ms-original-url').split('/api') | Select-Object -First 1

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($graphRequest)
        }) -clobber

}
