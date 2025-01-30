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
    $tenantFilter = $Request.Body.tenantFilter
    $User = $Request.headers.'x-ms-client-principal'
    Write-LogMessage -user $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    $Params = @{
        Identity = $Request.Body.GUID
    }

    try {
        $Params = @{ Identity = $Request.Body.GUID }

        $null = New-ExoRequest -tenantid $tenantFilter -cmdlet 'Remove-MailContact' -cmdParams $params -UseSystemMailbox $true
        $Result = "Deleted $($Request.Body.GUID)"
        Write-LogMessage -user $User -API $APIName -tenant $tenantFilter -message "Deleted contact $($Request.Body.GUID)" -sev Debug
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $User -API $APIName -tenant $tenantFilter -message "Failed to delete contact $($Request.Body.GUID). $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $Result = $ErrorMessage.NormalizedError
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = $Result }
        })

}
