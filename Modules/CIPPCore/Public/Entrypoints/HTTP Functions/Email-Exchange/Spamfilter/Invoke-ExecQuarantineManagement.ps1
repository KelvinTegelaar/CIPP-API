function Invoke-ExecQuarantineManagement {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    # Interact with query parameters or the body of the request.
    try {
        $TenantFilter = $Request.Body.tenantFilter | Select-Object -First 1
        $params = @{
            AllowSender  = [boolean]$Request.Body.AllowSender
            ReleaseToAll = $true
            ActionType   = ($Request.Body.Type | Select-Object -First 1)
        }
        if ($Request.Body.Identity -is [string]) {
            $params['Identity'] = $Request.Body.Identity
        } else {
            $params['Identities'] = $Request.Body.Identity
        }
        New-ExoRequest -tenantid $TenantFilter -cmdlet 'Release-QuarantineMessage' -cmdParams $Params
        $Results = [pscustomobject]@{'Results' = "Successfully processed $($Request.Body.Identity)" }
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $TenantFilter -message "Successfully processed Quarantine ID $($Request.Body.Identity)" -Sev 'Info'
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $TenantFilter -message "Quarantine Management failed: $($_.Exception.Message)" -Sev 'Error' -LogData $_
        $Results = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
