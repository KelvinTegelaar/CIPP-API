using namespace System.Net

Function Invoke-RemoveContact {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Contact.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $Tenantfilter = $request.Query.tenantfilter
    $User = $request.headers.'x-ms-client-principal'
    Write-LogMessage -user $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    $Params = @{
        Identity = $request.query.guid
    }

    try {
        $Params = @{ Identity = $request.query.GUID }

        $null = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Remove-MailContact' -cmdParams $params -UseSystemMailbox $true
        $Result = "Deleted $($Request.query.guid)"
        Write-LogMessage -user $User -API $APIName -tenant $tenantfilter -message "Deleted contact $($Request.query.guid)" -sev Debug
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $User -API $APIName -tenant $tenantfilter -message "Failed to delete contact $($Request.query.guid). $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $Result = $ErrorMessage.NormalizedError
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = $Result }
        })

}
