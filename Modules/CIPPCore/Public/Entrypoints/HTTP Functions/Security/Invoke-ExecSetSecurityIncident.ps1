using namespace System.Net

Function Invoke-ExecSetSecurityIncident {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.Incident.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $first = ''
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $IncidentFilter = $Request.Query.GUID ?? $Request.Body.GUID
    $Status = $Request.Query.Status ?? $Request.Body.Status
    # $Assigned = $Request.Query.Assigned ?? $Request.Body.Assigned ?? $Headers.'x-ms-client-principal'
    $Assigned = $Request.Query.Assigned ?? $Request.Body.Assigned ?? ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
    $Classification = $Request.Query.Classification ?? $Request.Body.Classification
    $Determination = $Request.Query.Determination ?? $Request.Body.Determination
    $Redirected = $Request.Query.Redirected -as [int] ?? $Request.Body.Redirected -as [int]
    $BodyBuild
    $AssignBody = '{'

    try {
        # We won't update redirected incidents because the incident it is redirected to should instead be updated
        if ($Redirected -lt 1) {
            # Set received status
            if ($null -ne $Status) {
                $AssignBody += $first + '"status":"' + $Status + '"'
                $BodyBuild += $first + 'Set status for incident ' + $IncidentFilter + ' to ' + $Status
                $first = ', '
            }

            # Set received classification and determination
            if ($null -ne $Classification) {
                if ($null -eq $Determination) {
                    # Maybe some poindexter tries to send a classification without a determination
                    throw
                }

                $AssignBody += $first + '"classification":"' + $Classification + '", "determination":"' + $Determination + '"'
                $BodyBuild += $first + 'Set classification & determination for incident ' + $IncidentFilter + ' to ' + $Classification + ' ' + $Determination
                $first = ', '
            }

            # Set received assignee
            if ($null -ne $Assigned) {
                $AssignBody += $first + '"assignedTo":"' + $Assigned + '"'
                if ($null -eq $Status) {
                    $BodyBuild += $first + 'Set assigned for incident ' + $IncidentFilter + ' to ' + $Assigned
                }
                $first = ', '
            }

            $AssignBody += '}'

            $ResponseBody = [pscustomobject]@{'Results' = $BodyBuild }
            New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/security/incidents/$IncidentFilter" -type PATCH -tenantid $TenantFilter -body $AssignBody -asApp $true
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Update incident $IncidentFilter with values $AssignBody" -Sev 'Info'
        } else {
            $ResponseBody = [pscustomobject]@{'Results' = "Refused to update incident $IncidentFilter with values $AssignBody because it is redirected to another incident" }
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Refused to update incident $IncidentFilter with values $AssignBody because it is redirected to another incident" -Sev 'Info'
        }

        $body = $ResponseBody
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to update incident $IncidentFilter : $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        $body = [pscustomobject]@{'Results' = $Result }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })

}
