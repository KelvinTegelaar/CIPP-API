using namespace System.Net

Function Invoke-ExecEnableArchive {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $ID = $Request.Query.id ?? $Request.Body.id

    Try {
        $ResultsArch = Set-CIPPMailboxArchive -userid $ID -tenantFilter $TenantFilter -APIName $APINAME -Headers $Request.Headers -ArchiveEnabled $true
        if ($ResultsArch -like 'Failed to set archive*') { throw $ResultsArch }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ResultsArch = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    $Results = [pscustomobject]@{'Results' = "$ResultsArch" }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
