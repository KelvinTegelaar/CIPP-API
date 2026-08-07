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
        # Cased as Exchange returns them. Select-Object matches property names
        # case-insensitively but emits the object's own casing, so asking for IMAPEnabled
        # still yields ImapEnabled on the wire - and JSON is case-sensitive, so a caller
        # keying on the name written here would find nothing.
        $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-CasMailbox' | Select-Object DisplayName, PrimarySmtpAddress, Guid, ECPEnabled, OWAEnabled, ImapEnabled, PopEnabled, MAPIEnabled, EwsEnabled, ActiveSyncEnabled, SmtpClientAuthenticationDisabled
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
