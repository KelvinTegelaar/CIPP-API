function Invoke-ListSharepointAdminUrl {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param(
        $Request,
        $TriggerMetadata
    )

    if ($Request.Query.TenantFilter) {
        $TenantFilter = $Request.Query.TenantFilter

        $Tenant = Get-Tenants -TenantFilter $TenantFilter

        if ($Tenant.SharepointAdminUrl) {
            $AdminUrl = $Tenant.SharepointAdminUrl
        } else {
            $tenantName = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/sites/root' -asApp $true -tenantid $TenantFilter).id.Split('.')[0]
            $AdminUrl = "https://$($tenantName)-admin.sharepoint.com"
            $Tenant | Add-Member -MemberType NoteProperty -Name SharepointAdminUrl -Value $AdminUrl
            $Table = Get-CIPPTable -TableName 'Tenants'
            Add-CIPPAzDataTableEntity @Table -Entity $Tenant -Force
        }

        if ($Request.Query.ReturnUrl) {
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @{
                        AdminUrl = $AdminUrl
                    }
                })
        } else {
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Found
                    Headers    = @{
                        Location = $AdminUrl
                    }
                })
        }
    } else {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'TenantFilter is required'
            })
    }
}
