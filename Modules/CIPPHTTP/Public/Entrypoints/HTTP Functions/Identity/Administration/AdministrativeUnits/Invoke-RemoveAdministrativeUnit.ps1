function Invoke-RemoveAdministrativeUnit {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.ReadWrite
    .DESCRIPTION
        Deletes an administrative unit. Its members are not deleted, but every role assignment scoped to the unit
        stops applying, and Exchange role assignments scoped to it no longer reach any mailbox. A deleted unit can
        be restored from the Entra recycle bin for 30 days.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter
    # Object id of the administrative unit.
    $ID = $Request.Body.ID
    $Name = $Request.Body.displayName ?? $ID

    if ([string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Error: tenantFilter is required and must be a single tenant' }
            })
    }
    if ([string]::IsNullOrWhiteSpace($ID) -or -not (Test-IsGuid -String $ID)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Error: ID must be the object id of an administrative unit' }
            })
    }

    try {
        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/directory/administrativeUnits/$ID" -tenantid $TenantFilter -type DELETE
        $Result = "Deleted administrative unit '$Name'"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to delete administrative unit '$Name': $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
