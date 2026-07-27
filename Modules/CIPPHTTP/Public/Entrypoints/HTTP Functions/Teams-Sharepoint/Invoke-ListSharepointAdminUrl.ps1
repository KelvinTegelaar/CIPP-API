function Invoke-ListSharepointAdminUrl {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Retrieves the SharePoint Admin Center URL for a tenant and redirects to it. Pass ReturnUrl to
        get the URL back as JSON instead of being redirected.

        The URL cannot be derived from the tenant name - it has to be resolved through Graph - so the
        result is cached on the tenant, which lets ListTenants hand out a direct link from then on.
    #>
    [CmdletBinding()]
    param(
        $Request,
        $TriggerMetadata
    )

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.TenantFilter

    if (!$TenantFilter) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'TenantFilter is required' }
            })
    }

    try {
        $Tenant = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1
        if (!$Tenant) {
            throw "Tenant '$TenantFilter' was not found."
        }

        if ($Tenant.SharepointAdminUrl) {
            $AdminUrl = $Tenant.SharepointAdminUrl
        } else {
            # Throws rather than returning a placeholder if the name can't be resolved, so we never
            # cache a URL that points nowhere.
            $AdminUrl = (Get-SharePointAdminLink -Public $false -TenantFilter $TenantFilter).AdminUrl

            $Tenant | Add-Member -MemberType NoteProperty -Name 'SharepointAdminUrl' -Value $AdminUrl -Force
            $Table = Get-CIPPTable -TableName 'Tenants'
            Add-CIPPAzDataTableEntity @Table -Entity $Tenant -Force
        }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to resolve the SharePoint admin URL: $ErrorMessage" -Sev 'Error'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ Results = "Could not resolve the SharePoint admin URL for $TenantFilter. $ErrorMessage" }
            })
    }

    if ($Request.Query.ReturnUrl) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ AdminUrl = $AdminUrl }
            })
    }

    # The body is not decoration: a browser that follows the redirect never sees it, but it means a
    # caller whose runtime drops the Location header gets the URL instead of a bare 'null' page.
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::Found
            Headers    = @{ Location = $AdminUrl }
            Body       = @{ AdminUrl = $AdminUrl }
        })
}
