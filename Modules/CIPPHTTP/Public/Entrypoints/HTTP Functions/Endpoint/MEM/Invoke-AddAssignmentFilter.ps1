function Invoke-AddAssignmentFilter {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $SelectedTenants = if ('AllTenants' -in $Request.body.tenantFilter) { (Get-Tenants).defaultDomainName } else { $Request.body.tenantFilter.value ? $Request.body.tenantFilter.value : $Request.body.tenantFilter }

    $FilterObject = $Request.body

    $Results = foreach ($tenant in $SelectedTenants) {
        try {
            # Use the centralized New-CIPPAssignmentFilter function
            $Result = New-CIPPAssignmentFilter -FilterObject $FilterObject -TenantFilter $tenant -APIName $APIName -ExecutingUser $Headers.'x-ms-client-principal-name'

            if ($Result.Success) {
                "Successfully created assignment filter $($FilterObject.displayName) for $($tenant)"
                $StatusCode = [HttpStatusCode]::OK
            } else {
                throw $Result.Message
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -headers $Headers -API $APIName -tenant $tenant -message "Assignment filter creation API failed. $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            "Failed to create assignment filter $($FilterObject.displayName) for $($tenant): $($ErrorMessage.NormalizedError)"
            $StatusCode = [HttpStatusCode]::InternalServerError
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = @($Results) }
        })
}
