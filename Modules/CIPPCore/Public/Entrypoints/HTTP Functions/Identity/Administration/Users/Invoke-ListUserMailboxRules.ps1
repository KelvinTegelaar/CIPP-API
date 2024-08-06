using namespace System.Net

Function Invoke-ListUserMailboxRules {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $User = $request.headers.'x-ms-client-principal'
    Write-LogMessage -user $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    try {
        $TenantFilter = $Request.Query.TenantFilter
        $UserID = $Request.Query.UserID
        $UserEmail = if ([string]::IsNullOrWhiteSpace($Request.Query.userEmail)) { $UserID } else { $Request.Query.userEmail }
        $GraphRequest = New-ExoRequest -Anchor $UserID -tenantid $TenantFilter -cmdlet 'Get-InboxRule' -cmdParams @{mailbox = $UserID; IncludeHidden = $true } | Where-Object { $_.Name -ne 'Junk E-Mail Rule' } | Select-Object
        @{ Name = 'DisplayName'; Expression = { $_.displayName } },
        @{ Name = 'Description'; Expression = { $_.Description } },
        @{ Name = 'Redirect To'; Expression = { $_.RedirectTo } },
        @{ Name = 'Copy To Folder'; Expression = { $_.CopyToFolder } },
        @{ Name = 'Move To Folder'; Expression = { $_.MoveToFolder } },
        @{ Name = 'Soft Delete Message'; Expression = { $_.SoftDeleteMessage } },
        @{ Name = 'Delete Message'; Expression = { $_.DeleteMessage } }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $User -API $APINAME -message "Failed to retrieve mailbox rules $($UserEmail): $($ErrorMessage.NormalizedError) " -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        # Associate values to output bindings by calling 'Push-OutputBinding'.
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = '500'
                Body       = $ErrorMessage.NormalizedError
            })
        exit
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}
