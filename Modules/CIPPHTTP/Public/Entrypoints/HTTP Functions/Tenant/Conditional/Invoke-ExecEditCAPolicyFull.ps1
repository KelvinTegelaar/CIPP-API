function Invoke-ExecEditCAPolicyFull {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

    if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ Results = 'Error: tenantFilter is required' }
        }
    }

    $PolicyId = $Request.Query.PolicyId ?? $Request.Body.PolicyId
    if ([string]::IsNullOrWhiteSpace($PolicyId)) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ Results = 'Error: PolicyId is required' }
        }
    }

    try {
        $PolicyBody = $Request.Body.PolicyBody
        if ($null -eq $PolicyBody) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Error: PolicyBody is required' }
            }
        }

        # Strip read-only properties that cannot be PATCHed
        $CleanBody = $PolicyBody | Select-Object -Property * -ExcludeProperty id, createdDateTime, modifiedDateTime, templateId
        # Round-trip so the canonicalizer always sees a PSCustomObject, whatever shape the request
        # body deserialised into, then apply the same rules the template deploy path uses: managed
        # keys the body omits are restored as their cleared form (that is how a PATCH clears an
        # assignment) and a condition block Graph would reject half-populated becomes null instead.
        $PolicyObject = ConvertTo-Json -InputObject $CleanBody -Depth 20 | ConvertFrom-Json
        Format-CIPPCAPolicy -Policy $PolicyObject
        $RawJSON = ConvertTo-Json -InputObject $PolicyObject -Depth 20 -Compress

        $null = New-GraphPOSTRequest `
            -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$PolicyId" `
            -tenantid $TenantFilter `
            -type PATCH `
            -body $RawJSON `
            -asApp $true

        $DisplayName = $PolicyBody.displayName ?? $PolicyId
        $Result = "Successfully updated CA policy '$DisplayName' for $TenantFilter"
        Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message $Result -sev Info
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to update CA policy $PolicyId for ${TenantFilter}: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode ?? [HttpStatusCode]::OK
        Body       = @{ Results = $Result }
    }
}
