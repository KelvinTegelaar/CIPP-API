using namespace System.Net

function Invoke-ExecConvertMailbox {
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

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $UserID = $Request.Body.ID
    $MailboxType = $Request.Body.MailboxType

    try {
        $Results = Set-CIPPMailboxType -UserID $UserID -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers -MailboxType $MailboxType
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{'Results' = $Results }
    }

}
