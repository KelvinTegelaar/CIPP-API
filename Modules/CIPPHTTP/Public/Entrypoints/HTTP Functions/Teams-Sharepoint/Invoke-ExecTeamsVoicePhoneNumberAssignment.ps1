Function Invoke-ExecTeamsVoicePhoneNumberAssignment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Voice.ReadWrite
    .DESCRIPTION
        Assigns a phone number to a user or resource account, or sets the emergency location on a
        number, via the Teams administration Graph API.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $Identity = $Request.Body.input.value
    $PhoneNumber = $Request.Body.PhoneNumber
    $TenantFilter = $Request.Body.TenantFilter
    $BaseUri = 'https://graph.microsoft.com/v1.0/admin/teams/telephoneNumberManagement/numberAssignments'

    try {
        if ($Request.Body.locationOnly) {
            # updateNumber is synchronous (200) and only touches the optional attributes.
            $Body = @{
                telephoneNumber = $PhoneNumber
                locationId      = $Identity
            }
            $null = New-GraphPOSTRequest -uri "$BaseUri/updateNumber" -tenantid $TenantFilter -body ($Body | ConvertTo-Json -Compress) -type POST
            $Results = [pscustomobject]@{'Results' = "Successfully assigned emergency location to $PhoneNumber" }
        } else {
            # Graph wants the object ID; the UI sends a UPN, so resolve it when it isn't a GUID.
            $TargetId = $Identity
            if ($Identity -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
                $TargetId = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$([uri]::EscapeDataString($Identity))?`$select=id" -tenantid $TenantFilter).id
                if (-not $TargetId) { throw "Could not resolve $Identity to a user or resource account." }
            }

            $Body = @{
                telephoneNumber    = $PhoneNumber
                assignmentTargetId = $TargetId
                numberType         = Get-CippTeamsNumberType -NumberType $Request.Body.PhoneNumberType
            }
            if ($Request.Body.AssignmentCategory) { $Body.assignmentCategory = $Request.Body.AssignmentCategory }

            # assignNumber is asynchronous: 202 Accepted with a Location header for the operation.
            $null = New-GraphPOSTRequest -uri "$BaseUri/assignNumber" -tenantid $TenantFilter -body ($Body | ConvertTo-Json -Compress) -type POST
            $Results = [pscustomobject]@{'Results' = "Successfully submitted assignment of $PhoneNumber to $Identity" }
        }
        Write-LogMessage -Headers $Headers -API $APINAME -tenant $($TenantFilter) -message $($Results.Results) -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = [pscustomobject]@{'Results' = $ErrorMessage.NormalizedError }
        Write-LogMessage -Headers $Headers -API $APINAME -tenant $($TenantFilter) -message $($Results.Results) -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
