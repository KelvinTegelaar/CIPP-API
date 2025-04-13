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
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $TenantId = (Get-Tenants | Where-Object -Property defaultDomainName -EQ $TenantFilter).customerId
    try {
        $Users = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=999&`$select=id,userPrincipalName,displayName" -tenantid $TenantFilter)
        $Skip = 0
        $GraphRequest = do {
            Write-Host "Getting page $Skip"
            $data = (New-TeamsAPIGetRequest -uri "https://api.interfaces.records.teams.microsoft.com/Skype.TelephoneNumberMgmt/Tenants/$($TenantId)/telephone-numbers?skip=$($Skip)&locale=en-US&top=999" -tenantid $TenantFilter).TelephoneNumbers | ForEach-Object {
                Write-Host 'Reached the loop'
                $CompleteRequest = $_ | Select-Object *, @{Name = 'AssignedTo'; Expression = { $users | Where-Object -Property id -EQ $_.AssignedTo.id } }
                if ($CompleteRequest.AcquisitionDate) {
                    $CompleteRequest.AcquisitionDate = $_.AcquisitionDate -split 'T' | Select-Object -First 1
                } else {
                    $CompleteRequest | Add-Member -NotePropertyName 'AcquisitionDate' -NotePropertyValue 'Unknown' -Force
                }
                $CompleteRequest.AssignedTo ? $null : ($CompleteRequest | Add-Member -NotePropertyName 'AssignedTo' -NotePropertyValue 'Unassigned' -Force)
                $CompleteRequest
            }
            Write-Host 'Finished the loop'
            $Skip = $Skip + 999
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
