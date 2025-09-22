using namespace System.Net

function Invoke-ExecSetMdoAlert {
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

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $AlertId = $Request.Query.GUID ?? $Request.Body.GUID
    $Status = $Request.Query.Status ?? $Request.Body.Status
    $Assigned = $Request.Query.Assigned ?? $Request.Body.Assigned ?? ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
    $Classification = $Request.Query.Classification ?? $Request.Body.Classification
    $Determination = $Request.Query.Determination ?? $Request.Body.Determination
    $Result = ''
    $AssignBody = @{}

    try {
        # Set received status
        if ($null -ne $Status) {
            $AssignBody.status = $Status
            $Result += 'Set status for incident ' + $AlertId + ' to ' + $Status
        }

        # Set received classification and determination
        if ($null -ne $Classification) {
            if ($null -eq $Determination) {
                # Maybe some poindexter tries to send a classification without a determination
                throw
            }

            $AssignBody.classification = $Classification
            $AssignBody.determination = $Determination
            $Result += 'Set classification & determination for incident ' + $AlertId + ' to ' + $Classification + ' ' + $Determination
        }

        # Set received assignee
        if ($null -ne $Assigned) {
            $AssignBody.assignedTo = $Assigned
            if ($null -eq $Status) {
                $Result += 'Set assigned for incident ' + $AlertId + ' to ' + $Assigned
            }
        }

        # Convert hashtable to JSON
        $AssignBodyJson = $AssignBody | ConvertTo-Json -Compress

        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/security/alerts_v2/$AlertId" -type PATCH -tenantid $TenantFilter -body $AssignBodyJson -asApp $true
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to update incident $AlertId : $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })

}
