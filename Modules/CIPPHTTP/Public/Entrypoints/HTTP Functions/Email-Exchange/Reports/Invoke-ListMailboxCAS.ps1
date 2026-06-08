function Invoke-ListMailboxCAS {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Lists Client Access Settings (CAS) for Exchange Online mailboxes, showing which protocols are enabled (OWA, IMAP, POP, MAPI, EWS, ActiveSync).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    try {
        $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-CasMailbox' | Select-Object DisplayName, PrimarySmtpAddress, Guid, ECPEnabled, OWAEnabled, IMAPEnabled, POPEnabled, MAPIEnabled, EWSEnabled, ActiveSyncEnabled, SmtpClientAuthenticationDisabled
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
