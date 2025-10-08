function Invoke-ExecRemoveRestrictedUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    .DESCRIPTION
        Removes a user from the restricted senders list in Exchange Online.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $SenderAddress = $Request.Body.SenderAddress

    try {
        if ([string]::IsNullOrEmpty($SenderAddress)) { throw 'SenderAddress parameter is required' }
        if ([string]::IsNullOrEmpty($TenantFilter)) { throw 'tenantFilter parameter is required' }

        # Remove the user from the restricted list
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-BlockedSenderAddress' -cmdParams @{SenderAddress = $SenderAddress }
        $Results = "Successfully removed $SenderAddress from the restricted users list."


        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Info' -tenant $TenantFilter
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to remove $SenderAddress from restricted list: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Results }
        })
}
