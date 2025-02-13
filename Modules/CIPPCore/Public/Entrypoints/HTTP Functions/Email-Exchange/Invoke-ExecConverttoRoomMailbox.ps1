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
    $User = $Request.Headers
    Write-LogMessage -Headers $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    Try {
        $ConvertedMailbox = Set-CIPPMailboxType -userid $Request.query.id -tenantFilter $Request.query.TenantFilter -APIName $APINAME -Headers $User -MailboxType 'Room'
        $Results = [pscustomobject]@{'Results' = "$ConvertedMailbox" }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $Results = [pscustomobject]@{'Results' = "Failed to convert $($request.query.id) - $ErrorMessage" }
        $StatusCode = [HttpStatusCode]::Forbidden
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
