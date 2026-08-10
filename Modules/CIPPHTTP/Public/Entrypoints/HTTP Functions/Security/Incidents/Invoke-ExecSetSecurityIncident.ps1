function Invoke-ExecSetSecurityIncident {
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


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $IncidentFilter = $Request.Body.GUID
    $Status = $Request.Body.Status
    $Classification = $Request.Body.Classification
    $Determination = $Request.Body.Determination
    # Severity autoComplete submits {label, value}
    $Severity = $Request.Body.Severity.value
    $Comment = $Request.Body.Comment
    $Redirected = $Request.Body.Redirected -as [int]

    $AssignToSelf = [System.Convert]::ToBoolean($Request.Body.AssignToSelf)
    # Assign-to-self resolves to the caller; other actions omit the assignee so it's preserved.
    if ($AssignToSelf -eq $true) {
        $Assigned = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
    }

    # Hashtable + ConvertTo-Json so free-text fields (resolvingComment) are escaped correctly.
    $BodyObject = [ordered]@{}
    $BodyParts = [System.Collections.Generic.List[string]]::new()

    try {
        # We won't update redirected incidents because the incident it is redirected to should instead be updated
        if ($Redirected -lt 1) {
            # Set received status
            if ($null -ne $Status) {
                $BodyObject['status'] = $Status
                $BodyParts.Add("status to $Status")
            }

            # Set received severity
            if ($null -ne $Severity) {
                $BodyObject['severity'] = $Severity
                $BodyParts.Add("severity to $Severity")
            }

            # Set received classification and determination
            if ($null -ne $Classification) {
                if ($null -eq $Determination) {
                    # Maybe some poindexter tries to send a classification without a determination
                    throw
                }

                $BodyObject['classification'] = $Classification
                $BodyObject['determination'] = $Determination
                $BodyParts.Add("classification & determination to $Classification $Determination")
            }

            # Set received resolving comment
            if ($null -ne $Comment) {
                $BodyObject['resolvingComment'] = $Comment
                $BodyParts.Add('resolving comment')
            }

            # Set received assignee
            if ($null -ne $Assigned) {
                $BodyObject['assignedTo'] = $Assigned
                if ($null -eq $Status) {
                    $BodyParts.Add("assigned to $Assigned")
                }
            }

            $AssignBody = ConvertTo-Json -InputObject $BodyObject -Compress
            $BodyBuild = "Set $($BodyParts -join ', ') for incident $IncidentFilter"

            $Result = $BodyBuild
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/security/incidents/$IncidentFilter" -type PATCH -tenantid $TenantFilter -body $AssignBody -asApp $true
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Update incident $IncidentFilter with values $AssignBody" -Sev 'Info'
        } else {
            $Result = "Refused to update incident $IncidentFilter because it is redirected to another incident"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to update incident $IncidentFilter : $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Result }
        })

}
