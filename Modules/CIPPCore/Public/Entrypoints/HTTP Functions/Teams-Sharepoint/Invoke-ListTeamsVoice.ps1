using namespace System.Net

Function Invoke-ListTeamsVoice {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Voice.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $tenantid = (Get-Tenants | Where-Object -Property defaultDomainName -EQ $Request.Query.TenantFilter).customerId
    try {
        $users = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=999&`$select=id,userPrincipalName,displayName" -tenantid $TenantFilter)
        $skip = 0
        $GraphRequest = do {
            Write-Host "Getting page $skip"
            $data = (New-TeamsAPIGetRequest -uri "https://api.interfaces.records.teams.microsoft.com/Skype.TelephoneNumberMgmt/Tenants/$($Tenantid)/telephone-numbers?skip=$($skip)&locale=en-US&top=999" -tenantid $TenantFilter).TelephoneNumbers | ForEach-Object {
                Write-Host 'Reached the loop'
                $CompleteRequest = $_ | Select-Object *, @{Name = 'AssignedTo'; Expression = { $users | Where-Object -Property id -EQ $_.AssignedTo.id } }
                $CompleteRequest.AcquisitionDate ? ($CompleteRequest.AcquisitionDate = $CompleteRequest.AcquisitionDate -split 'T' | Select-Object -First 1) : ($CompleteRequest | Add-Member -NotePropertyName 'AcquisitionDate' -NotePropertyValue 'Unknown' -Force)
                $CompleteRequest.AssignedTo ? $null : ($CompleteRequest | Add-Member -NotePropertyName 'AssignedTo' -NotePropertyValue 'Unassigned' -Force)
                $CompleteRequest
            }
            Write-Host 'Finished the loop'
            $skip = $skip + 999
            $Data
        } while ($data.Count -eq 999)
        Write-Host 'Exiting the Do.'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    Write-Host "Graph request is: $($GraphRequest)"
    Write-Host 'Returning the response'
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
