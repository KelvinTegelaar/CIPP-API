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
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

    # Interact with query parameters or the body of the request.
    $GUID = $Request.query.GUID ?? $Request.body.GUID
    $Mail = $Request.query.Mail ?? $Request.body.Mail

    try {
        $Params = @{
            Identity = $GUID
        }
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-MailContact' -cmdParams $Params -UseSystemMailbox $true
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Deleted contact $GUID" -sev 'Info'
        $Result = "Deleted $Mail"
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to delete contact $GUID. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    $Results = [pscustomobject]@{'Results' = $Result }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
