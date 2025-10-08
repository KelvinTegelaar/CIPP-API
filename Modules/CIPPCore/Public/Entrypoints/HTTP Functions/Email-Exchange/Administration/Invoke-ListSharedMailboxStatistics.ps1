Function Invoke-ListSharedMailboxStatistics {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # XXX Seems like an unused endpoint? -Bobby

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    try {
        $GraphRequest = New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($tenantFilter)/Mailbox?RecipientTypeDetails=sharedmailbox" -Tenantid $tenantFilter -scope ExchangeOnline | ForEach-Object {
            try {
                New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxStatistics' -cmdParams @{Identity = $_.GUID }
            } catch {
                continue
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
