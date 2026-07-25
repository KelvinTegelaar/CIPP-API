function Invoke-ListTeamsVoice {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Voice.Read
    .DESCRIPTION
        Lists Microsoft Teams voice and PSTN usage for a tenant. Supports UseReportDB=true query parameter to retrieve cached data from the reporting database for significantly better performance, especially when querying AllTenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $UseReportDB = $Request.Query.UseReportDB
    try {
        if ($TenantFilter -eq 'AllTenants' -or $UseReportDB -eq 'true') {
            try {
                $GraphRequest = Get-CIPPTeamsVoiceReport -TenantFilter $TenantFilter -ErrorAction Stop
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                $StatusCode = [HttpStatusCode]::InternalServerError
                $GraphRequest = $_.Exception.Message
            }
            return ([HttpResponseContext]@{
                    StatusCode = $StatusCode
                    Body       = @($GraphRequest)
                })
        }

        $TenantId = (Get-Tenants -TenantFilter $TenantFilter).customerId
        $Users = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=999&`$select=id,userPrincipalName,displayName" -tenantid $TenantFilter)
        # The number list only carries LocationId GUIDs; resolve them to a readable label.
        $LocationLookup = Get-CippTeamsLocationLookup -TenantFilter $TenantFilter
        $Skip = 0
        $GraphRequest = do {
            Write-Host "Getting page $Skip"
            $Results = New-TeamsRequestV2 -TenantFilter $TenantFilter -Path "Skype.TelephoneNumberMgmt/Tenants/$TenantId/telephone-numbers" `
                -QueryParameters @{ skip = $Skip; locale = 'en-US'; top = 999 } `
                -AdditionalHeaders @{ 'x-ms-tnm-applicationid' = '045268c0-445e-4ac1-9157-d58f67b167d9' }
            #Write-Information ($Results | ConvertTo-Json -Depth 10)
            $data = $Results.TelephoneNumbers | ForEach-Object {
                $CompleteRequest = $_ | Select-Object *,
                @{Name = 'AssignedTo'; Expression = { $users | Where-Object -Property id -EQ $_.TargetId } },
                @{Name = 'EmergencyLocation'; Expression = { if ($_.LocationId) { $LocationLookup[[string]$_.LocationId] } } }
                if ($CompleteRequest.AcquisitionDate) {
                    $CompleteRequest.AcquisitionDate = $_.AcquisitionDate -split 'T' | Select-Object -First 1
                } else {
                    $CompleteRequest | Add-Member -NotePropertyName 'AcquisitionDate' -NotePropertyValue 'Unknown' -Force
                }
                $CompleteRequest.AssignedTo ? $null : ($CompleteRequest | Add-Member -NotePropertyName 'AssignedTo' -NotePropertyValue 'Unassigned' -Force)
                $CompleteRequest
            }
            $Skip = $Skip + 999
            $Data
        } while ($data.Count -eq 999)
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    Write-Host "Graph request is: $($GraphRequest)"
    Write-Host 'Returning the response'
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest | Where-Object { $_.TelephoneNumber })
        })

}
