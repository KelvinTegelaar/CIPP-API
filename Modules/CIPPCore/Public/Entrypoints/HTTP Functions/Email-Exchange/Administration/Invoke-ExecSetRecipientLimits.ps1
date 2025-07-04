function Invoke-ExecSetRecipientLimits {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with the query or body of the request
    $TenantFilter = $Request.Body.tenantFilter
    $recipientLimit = $Request.Body.recipientLimit
    $Identity = $Request.Body.Identity
    $UserPrincipalName = $Request.Body.userid

    # Execute the EXO request
    try {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $Identity; RecipientLimits = $recipientLimit }
        $Results = "Recipient limit for $UserPrincipalName has been set to $recipientLimit"

        Write-LogMessage -API $APIName -tenant $TenantFilter -message $Results -headers $Headers -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Could not set recipient limit for $UserPrincipalName to $recipientLimit. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -tenant $TenantFilter -message $Results -headers $Headers -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = @($Results) }
    }
}
