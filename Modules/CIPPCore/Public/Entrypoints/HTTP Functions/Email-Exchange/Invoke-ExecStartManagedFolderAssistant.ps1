using namespace System.Net

Function Invoke-ExecStartManagedFolderAssistant {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $User = $request.headers.'x-ms-client-principal'
    Write-LogMessage -user $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    $Results = [System.Collections.Generic.List[Object]]::new()

    # Interact with query parameters or the body of the request.

    try {
        $null = New-ExoRequest -tenantid $($MailboxObject.tenantid) -cmdlet 'Start-ManagedFolderAssistant' -cmdparams @{Identity = $Request.query.id }
        $Results.Add("Successfully started Managed Folder Assistant for mailbox $($Request.query.id).")
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $User -API $APINAME -tenant $($MailboxObject.tenantid) -message "Failed to create room: $($MailboxObject.DisplayName). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Results.Add("Failed to start Managed Folder Assistant for mailbox $($Request.query.id). Error: $($ErrorMessage.NormalizedError)")
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    $Body = [pscustomobject] @{ 'Results' = @($Results) }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
