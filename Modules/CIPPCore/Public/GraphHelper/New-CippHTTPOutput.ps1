using namespace System.Net

function New-CippHTTPOutput {
    <#
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Type = 'Raw',
        [Parameter(Mandatory = $true)]
        [string]$Body
    )

    if ($type -eq 'Raw') {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $body
            })
    }
    if ($Type -eq 'Results') {
        #Make the status code dependant on the results. Throw a 500 if the errorState is true, add the copyFrom field, make sure Results is an array.
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $body
            })
    }

}
