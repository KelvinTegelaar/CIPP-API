using namespace System.Net

Function Invoke-ListTeamsVoice {
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
    $tenantid = (Get-Tenants | Where-Object -Property defaultDomainName -EQ $Request.Query.TenantFilter).customerId
    try {
        $users = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=999&`$select=id,userPrincipalName,displayname" -tenantid $TenantFilter)
        $GraphRequest = (New-TeamsAPIGetRequest -uri "https://api.interfaces.records.teams.microsoft.com/Skype.TelephoneNumberMgmt/Tenants/$($Tenantid)/telephone-numbers?locale=en-US" -tenantid $TenantFilter).TelephoneNumbers | ForEach-Object {
            $CompleteRequest = $_ | Select-Object *, 'AssignedTo'
            $CompleteRequest.AcquisitionDate = $CompleteRequest.AcquisitionDate -split 'T' | Select-Object -First 1

            if ($CompleteRequest.TargetId -eq '00000000-0000-0000-0000-000000000000') { 
                $CompleteRequest.AssignedTo = 'Unassigned'
            } else {
                $CompleteRequest.AssignedTo = ($users | Where-Object -Property Id -EQ $CompleteRequest.TargetId).userPrincipalName
       
            }
            $CompleteRequest
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
