using namespace System.Net

Function Invoke-ExecCopyForSent {
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
    Write-LogMessage -headers $Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter ?? $Request.Body.TenantFilter
    $UserID = $Request.Query.ID ?? $Request.Body.ID
    $MessageCopyForSentAsEnabled = $Request.Query.MessageCopyForSentAsEnabled ?? $Request.Body.MessageCopyForSentAsEnabled
    $MessageCopyForSentAsEnabled = [System.Convert]::ToBoolean($MessageCopyForSentAsEnabled)

    Try {
        $Result = Set-CIPPMessageCopy -userid $UserID -tenantFilter $TenantFilter -APIName $APIName -Headers $Headers -MessageCopyForSentAsEnabled $MessageCopyForSentAsEnabled
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "$($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Result }
        })

}
