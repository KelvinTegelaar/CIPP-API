function Invoke-AddDomain {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Body.tenantFilter
    $DomainName = $Request.Body.domain

    # Interact with query parameters or the body of the request.
    try {
        if ([string]::IsNullOrWhiteSpace($DomainName)) {
            throw 'Domain name is required'
        }

        # Validate domain name format
        if ($DomainName -notmatch '^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$') {
            throw 'Invalid domain name format'
        }

        Write-Information "Adding domain $DomainName to tenant $TenantFilter"

        $Body = @{
            id = $DomainName
        } | ConvertTo-Json -Compress

        $GraphRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/domains' -tenantid $TenantFilter -type POST -body $Body -AsApp $true

        $Result = "Successfully added domain $DomainName to tenant $TenantFilter. Please verify the domain to complete setup."
        Write-LogMessage -headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Added domain $DomainName" -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to add domain $DomainName`: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Failed to add domain $DomainName`: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })

}

