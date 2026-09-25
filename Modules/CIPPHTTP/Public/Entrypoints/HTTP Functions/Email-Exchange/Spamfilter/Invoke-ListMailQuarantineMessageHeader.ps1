function Invoke-ListMailQuarantineMessageHeader {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.Read
    .DESCRIPTION
        Retrieves the message headers of a specific quarantined email message by its Identity.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $Identity = $Request.Query.Identity

    try {
        $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-QuarantineMessageHeader' -cmdParams @{ 'Identity' = $Identity }
        # Headers are message content as far as the customer is concerned; record who viewed them.
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -tenant $TenantFilter -message "Viewed the headers of quarantined message $Identity" -Sev 'Info'
        $Body = @{
            'Identity' = $Identity
            'Header'   = [string]($GraphRequest.Header ?? $GraphRequest)
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $Body = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })

}
