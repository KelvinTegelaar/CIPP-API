using namespace System.Net

function Invoke-ListSharedMailboxStatistics {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

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
        $StatusCode = [HttpStatusCode]::InternalServerError
        $GraphRequest = $ErrorMessage
    }

    return @{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    }

}
