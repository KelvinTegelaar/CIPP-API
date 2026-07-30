function Invoke-ListSiteRoleDefinitions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Lists the permission levels defined on a SharePoint site via the SharePoint REST API with
        certificate authentication. Reading them from the site rather than assuming the five
        built-ins means custom permission levels are offered too. Hidden levels and Limited Access
        (RoleTypeKind 1, managed by SharePoint itself) are excluded by default because they must
        not be handed out manually; pass IncludeUnassignable to get the full list.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $SiteUrl = $Request.Query.SiteUrl ?? $Request.Body.SiteUrl
    $IncludeUnassignable = ($Request.Query.IncludeUnassignable ?? $Request.Body.IncludeUnassignable) -eq $true

    try {
        if ([string]::IsNullOrWhiteSpace($SiteUrl)) { throw 'SiteUrl is required.' }

        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $Scope = "$($SharePointInfo.SharePointUrl)/.default"
        $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }
        $BaseUri = "$($SiteUrl.TrimEnd('/'))/_api"

        $RoleDefinitions = @(New-GraphGetRequest -uri "$BaseUri/web/roledefinitions?`$select=Id,Name,Description,RoleTypeKind,Hidden,Order" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true)

        $Results = @($RoleDefinitions |
                Where-Object { $IncludeUnassignable -or ($_.Hidden -ne $true -and $_.RoleTypeKind -ne 1) } |
                Sort-Object -Property Order |
                ForEach-Object {
                    [PSCustomObject]@{
                        Id           = [string]$_.Id
                        Name         = $_.Name
                        Description  = $_.Description
                        RoleTypeKind = $_.RoleTypeKind
                        # Built-in levels carry a RoleTypeKind; custom ones are created as None (0).
                        IsCustom     = ($_.RoleTypeKind -eq 0)
                    }
                })
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to list permission levels: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })
}
