function Invoke-ListSharepointAdminUrl {
    <#
    .SYNOPSIS
    List SharePoint admin URL for a tenant
    
    .DESCRIPTION
    Retrieves or generates the SharePoint admin URL for a specific tenant with caching and optional redirect functionality
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
        
    .NOTES
    Group: Teams & SharePoint
    Summary: List Sharepoint Admin URL
    Description: Retrieves or generates the SharePoint admin URL for a specific tenant with caching in the Tenants table and optional redirect functionality
    Tags: SharePoint,Admin URL,Redirect
    Parameter: TenantFilter (string) [query] - Target tenant identifier (required)
    Parameter: ReturnUrl (boolean) [query] - Whether to return URL in response body (true) or redirect (false)
    Response: Returns different responses based on ReturnUrl parameter:
    Response: If ReturnUrl=true: Returns object with AdminUrl property and HTTP 200 status
    Response: If ReturnUrl=false: Returns HTTP 302 redirect to SharePoint admin URL
    Response: If TenantFilter missing: Returns error message with HTTP 400 status
    Example: {
      "AdminUrl": "https://contoso-admin.sharepoint.com"
    }
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
        }
        else {
            $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
            $Tenant | Add-Member -MemberType NoteProperty -Name SharepointAdminUrl -Value $SharePointInfo.AdminUrl
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
        }
        else {
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Found
                    Headers    = @{
                        Location = $AdminUrl
                    }
                })
        }
    }
    else {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'TenantFilter is required'
            })
    }
}
