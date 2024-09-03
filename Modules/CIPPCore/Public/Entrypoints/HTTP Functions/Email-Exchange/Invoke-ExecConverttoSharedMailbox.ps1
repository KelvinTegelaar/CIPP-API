using namespace System.Net

Function Invoke-ExecConverttoSharedMailbox {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $Tenant = $Request.query.TenantFilter
    $User = $request.headers.'x-ms-client-principal'
    Write-LogMessage -user $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'


    # Interact with query parameters or the body of the request.
    Try {
        $MailboxType = if ($request.query.ConvertToUser -eq 'true') { 'Regular' } else { 'Shared' }
        $ConvertedMailbox = Set-CIPPMailboxType -userid $Request.query.id -tenantFilter $Tenant -APIName $APINAME -ExecutingUser $User -MailboxType $MailboxType
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
