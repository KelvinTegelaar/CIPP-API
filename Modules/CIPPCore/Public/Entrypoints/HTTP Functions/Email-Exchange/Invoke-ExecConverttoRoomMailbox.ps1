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
        $Results = [pscustomobject]@{'Results' = "$ConvertedMailbox" }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = [pscustomobject]@{'Results' = "$($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::Forbidden
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
