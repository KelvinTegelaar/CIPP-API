Function Invoke-ExecGDAPInviteApproved {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message 'Started processing recently activated GDAP relationships' -Sev 'Info'
        Set-CIPPGDAPInviteGroups
        $body = @{Results = @('Processing recently activated GDAP relationships') }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Failed to process recently activated GDAP relationships: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $body = @{Results = @("Failed to process recently activated GDAP relationships: $($ErrorMessage.NormalizedError)") }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })

}
