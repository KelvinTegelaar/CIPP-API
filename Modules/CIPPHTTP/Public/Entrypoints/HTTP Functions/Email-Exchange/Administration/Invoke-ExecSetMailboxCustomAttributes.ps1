function Invoke-ExecSetMailboxCustomAttributes {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Interact with the query or body of the request
    $TenantFilter = $Request.Body.tenantFilter
    $Identity = $Request.Body.Identity
    $UserPrincipalName = $Request.Body.userid

    Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message 'Accessed this API' -Sev 'Debug'

    $CmdParams = @{
        Identity = $Identity
    }
    $UpdatedAttributes = [System.Collections.Generic.List[string]]::new()
    $BodyPropertyNames = @($Request.Body.PSObject.Properties.Name)

    foreach ($Index in 1..15) {
        $AttributeName = "CustomAttribute$Index"
        # Only set attributes present on the body (including empty string to clear).
        # Missing keys are left unchanged so bulk/selective edits do not wipe others.
        if ($AttributeName -in $BodyPropertyNames) {
            $CmdParams[$AttributeName] = [string]$Request.Body.$AttributeName
            $UpdatedAttributes.Add($AttributeName)
        }
    }

    if ($UpdatedAttributes.Count -eq 0) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'No custom attributes were provided to update' }
            })
    }

    $ExoRequest = @{
        tenantid  = $TenantFilter
        cmdlet    = 'Set-Mailbox'
        cmdParams = $CmdParams
    }

    $AttributeList = $UpdatedAttributes -join ', '

    try {
        $null = New-ExoRequest @ExoRequest
        $Results = "Custom attributes for $UserPrincipalName have been updated ($AttributeList)"

        Write-LogMessage -API $APIName -tenant $TenantFilter -message $Results -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Could not update custom attributes for $UserPrincipalName. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Results }
        })
}
