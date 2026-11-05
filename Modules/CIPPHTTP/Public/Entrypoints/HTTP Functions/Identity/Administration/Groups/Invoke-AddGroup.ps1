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
    $SelectedTenants = $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter
    if ('AllTenants' -in $SelectedTenants) { $SelectedTenants = (Get-Tenants).defaultDomainName }


    $GroupObject = $Request.body
    $Failed = 0

    $Results = foreach ($tenant in $SelectedTenants) {
        try {
            # Use the centralized New-CIPPGroup function
            $Result = New-CIPPGroup -GroupObject $GroupObject -TenantFilter $tenant -APIName $APIName -ExecutingUser $Request.Headers.'x-ms-client-principal-name'

            if ($Result.Success) {
                "Successfully created group $($GroupObject.displayName) for $($tenant)"
            } else {
                throw $Result.Message
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Failed to create group. $($GroupObject.displayName) for $($tenant) $($ErrorMessage.NormalizedError)"
            $Failed++
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = Get-CippBulkStatusCode -Total @($SelectedTenants).Count -Failed $Failed
            Body       = @{'Results' = @($Results) }
        })
}
