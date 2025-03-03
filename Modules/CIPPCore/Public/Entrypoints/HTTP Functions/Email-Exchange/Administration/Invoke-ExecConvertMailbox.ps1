using namespace System.Net

Function Invoke-ExecConvertMailbox {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Body.tenantFilter
    Write-LogMessage -Headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $UserID = $Request.Body.ID
    $MailboxType = $Request.Body.MailboxType

    try {
        $ConvertedMailbox = Set-CIPPMailboxType -UserID $UserID -TenantFilter $TenantFilter -APIName $APIName -Headers $Request.Headers -MailboxType $MailboxType
        if ($ConvertedMailbox -like 'Could not convert*') { throw $ConvertedMailbox }
        $Results = [pscustomobject]@{'Results' = "$ConvertedMailbox" }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = $_.Exception.Message
        $Results = [pscustomobject]@{'Results' = "$ErrorMessage" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
