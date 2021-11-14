using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

Import-Module .\DNSHelper.psm1

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'

$StatusCode = [HttpStatusCode]::OK
try {
    if ($Request.Query.Action) {

        switch ($Request.Query.Action) {
            'ReadSpfRecord' {
                if ($Request.Query.ExpectedInclude) {
                    $Body = Read-SpfRecord -Domain $Request.Query.Domain -ExpectedInclude $Request.Query.ExpectedInclude
                }
                else {
                    $Body = Read-SpfRecord -Domain $Request.Query.Domain
                }
            }
            'ReadDmarcPolicy' {
                $Body = Read-DmarcPolicy -Domain $Request.Query.Domain
            }
            'ReadDkimRecord' {
                $Body = Read-DkimRecord -Domain $Request.Query.Domain -Selector $Request.Query.Selector
            }
        }
    }
}
catch {
    Log-Request -API $APINAME -tenant $($name) -user $request.headers.'x-ms-client-principal' -message "DNS Test API failed. $($_.Exception.Message)" -Sev 'Error'
    $body = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
    $StatusCode = [HttpStatusCode]::BadRequest
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $body
    })
