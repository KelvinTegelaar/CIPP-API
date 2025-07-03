using namespace System.Net

function Invoke-RemoveContact {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Contact.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $GUID = $Request.query.GUID ?? $Request.body.GUID
    $Mail = $Request.query.Mail ?? $Request.body.Mail

    try {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-MailContact' -cmdParams @{Identity = $GUID } -UseSystemMailbox $true
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Deleted contact $Mail - $GUID" -Sev Info
        $Result = "Deleted contact $Mail - $GUID"
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to delete contact $GUID. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{Results = $Result }
    }

}
