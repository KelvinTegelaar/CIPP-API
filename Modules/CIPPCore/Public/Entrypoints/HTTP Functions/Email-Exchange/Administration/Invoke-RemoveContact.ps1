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

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter
    Write-LogMessage -Headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $GUID = $Request.query.GUID ?? $Request.body.GUID

    try {
        $Params = @{
            Identity = $GUID
        }
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-MailContact' -cmdParams $Params -UseSystemMailbox $true
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Deleted contact $GUID" -sev Debug
        $Result = "Deleted $GUID"
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to delete contact $GUID. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    $Results = [pscustomobject]@{'Results' = $Result }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
