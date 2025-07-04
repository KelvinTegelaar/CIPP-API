using namespace System.Net

function Invoke-ExecCopyForSent {
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
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter ?? $Request.Body.TenantFilter
    $UserID = $Request.Query.ID ?? $Request.Body.ID
    $MessageCopyForSentAsEnabled = $Request.Query.MessageCopyForSentAsEnabled ?? $Request.Body.MessageCopyForSentAsEnabled
    $MessageCopyForSentAsEnabled = [System.Convert]::ToBoolean($MessageCopyForSentAsEnabled)

    try {
        $Result = Set-CIPPMessageCopy -userid $UserID -tenantFilter $TenantFilter -APIName $APIName -Headers $Headers -MessageCopyForSentAsEnabled $MessageCopyForSentAsEnabled
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "$($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ 'Results' = $Result }
    }

}
