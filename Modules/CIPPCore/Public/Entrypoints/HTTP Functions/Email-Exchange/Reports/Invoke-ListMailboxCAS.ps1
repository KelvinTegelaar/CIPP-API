function Invoke-ListMailboxCAS {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    try {
        $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-CasMailbox' | Select-Object @{ Name = 'displayName'; Expression = { $_.'DisplayName' } },
        @{ Name = 'primarySmtpAddress'; Expression = { $_.'PrimarySMTPAddress' } },
        @{ Name = 'ecpenabled'; Expression = { $_.'ECPEnabled' } },
        @{ Name = 'owaenabled'; Expression = { $_.'OWAEnabled' } },
        @{ Name = 'imapenabled'; Expression = { $_.'IMAPEnabled' } },
        @{ Name = 'popenabled'; Expression = { $_.'POPEnabled' } },
        @{ Name = 'mapienabled'; Expression = { $_.'MAPIEnabled' } },
        @{ Name = 'ewsenabled'; Expression = { $_.'EWSEnabled' } },
        @{ Name = 'activesyncenabled'; Expression = { $_.'ActiveSyncEnabled' } }
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
