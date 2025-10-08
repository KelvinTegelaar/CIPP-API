function Invoke-AddGroup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Group.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $SelectedTenants = if ('AllTenants' -in $SelectedTenants) { (Get-Tenants).defaultDomainName } else { $Request.body.tenantFilter.value ? $Request.body.tenantFilter.value : $Request.body.tenantFilter }
    Write-LogMessage -headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev Debug


    $GroupObject = $Request.body

    $Results = foreach ($tenant in $SelectedTenants) {
        try {
            # Use the centralized New-CIPPGroup function
            $Result = New-CIPPGroup -GroupObject $GroupObject -TenantFilter $tenant -APIName $APIName -ExecutingUser $Request.Headers.'x-ms-client-principal-name'

            if ($Result.Success) {
                "Successfully created group $($GroupObject.displayName) for $($tenant)"
                $StatusCode = [HttpStatusCode]::OK
            } else {
                throw $Result.Message
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -headers $Request.Headers -API $APIName -tenant $tenant -message "Group creation API failed. $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            "Failed to create group. $($GroupObject.displayName) for $($tenant) $($ErrorMessage.NormalizedError)"
            $StatusCode = [HttpStatusCode]::InternalServerError
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = @($Results) }
        })
}
