using namespace System.Net

Function Invoke-ExecConvertToRoomMailbox {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    Write-LogMessage -Headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $UserID = $Request.Query.ID ?? $Request.Body.ID

    Try {
        $ConvertedMailbox = Set-CIPPMailboxType -UserID $UserID -TenantFilter $TenantFilter -APIName $APIName -Headers $Request.Headers -MailboxType 'Room'
        if ($ConvertedMailbox -like 'Could not convert*') { throw $ConvertedMailbox }
        $Results = [pscustomobject]@{'Results' = "$ConvertedMailbox" }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = $_.Exception.Message
        Write-LogMessage -Headers $Request.Headers -API $APIName -message "Error converting mailbox: $ErrorMessage" -Sev 'Error'
        $Results = [pscustomobject]@{'Results' = "$ErrorMessage" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
