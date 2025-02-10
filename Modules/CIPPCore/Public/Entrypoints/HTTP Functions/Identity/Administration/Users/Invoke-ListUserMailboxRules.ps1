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

    $APIName = $Request.Params.CIPPEndpoint
    $User = $Request.Headers
    Write-LogMessage -Headers $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    try {
        $TenantFilter = $Request.Query.TenantFilter
        $UserID = $Request.Query.UserID
        $UserEmail = if ([string]::IsNullOrWhiteSpace($Request.Query.userEmail)) { $UserID } else { $Request.Query.userEmail }
        $GraphRequest = New-ExoRequest -Anchor $UserID -tenantid $TenantFilter -cmdlet 'Get-InboxRule' -cmdParams @{mailbox = $UserID; IncludeHidden = $true } | Where-Object { $_.Name -ne 'Junk E-Mail Rule' -and $_.Name -notlike 'Microsoft.Exchange.OOF.*' } | Select-Object * -ExcludeProperty RuleIdentity
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $User -API $APINAME -message "Failed to retrieve mailbox rules $($UserEmail): $($ErrorMessage.NormalizedError) " -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
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
