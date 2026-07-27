Function Invoke-ExecRemoveTeamsVoicePhoneNumberAssignment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Voice.ReadWrite
    .DESCRIPTION
        Unassigns a phone number from a user or resource account via the Teams administration Graph API.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $AssignedTo = $Request.Body.AssignedTo
    $PhoneNumber = $Request.Body.PhoneNumber
    $PhoneNumberType = $Request.Body.PhoneNumberType

    try {
        # unassignNumber is keyed on the number alone - AssignedTo is kept only for the audit log.
        $Body = @{
            telephoneNumber = $PhoneNumber
            numberType      = Get-CippTeamsNumberType -NumberType $PhoneNumberType
        }
        # Asynchronous: 202 Accepted with a Location header for the operation.
        $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/admin/teams/telephoneNumberManagement/numberAssignments/unassignNumber' -tenantid $TenantFilter -body ($Body | ConvertTo-Json -Compress) -type POST
        $Result = "Successfully submitted unassignment of $PhoneNumber from $AssignedTo"
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to unassign $PhoneNumber from $AssignedTo. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}
