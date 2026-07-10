function Remove-CIPPSPOSiteUser {
    <#
    .SYNOPSIS
    Remove a user from one or more SharePoint sites entirely

    .DESCRIPTION
    Deletes the user from each site's user list via the SharePoint REST API with certificate
    authentication, which removes them from every site group and direct permission grant on
    that site at once. Site collection admins are refused (remove their admin flag first).

    .PARAMETER TenantFilter
    Tenant the sites belong to

    .PARAMETER SiteUrls
    One or more site URLs to remove the user from

    .PARAMETER LoginName
    SharePoint claims login (i:0#.f|membership|upn); a bare UPN is converted automatically

    .EXAMPLE
    Remove-CIPPSPOSiteUser -TenantFilter 'contoso.onmicrosoft.com' -SiteUrls @('https://contoso.sharepoint.com/sites/HR') -LoginName 'guest_example.com#ext#@contoso.onmicrosoft.com'

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [string[]]$SiteUrls,
        [Parameter(Mandatory = $true)]
        [string]$LoginName
    )

    if ($LoginName -notmatch '\|') { $LoginName = "i:0#.f|membership|$LoginName" }

    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    $Scope = "$($SharePointInfo.SharePointUrl)/.default"
    $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }

    $Succeeded = [System.Collections.Generic.List[string]]::new()
    $Failed = [System.Collections.Generic.List[string]]::new()

    foreach ($SiteUrl in $SiteUrls) {
        if (-not $PSCmdlet.ShouldProcess($SiteUrl, "Remove $LoginName")) { continue }
        $BaseUri = "$($SiteUrl.TrimEnd('/'))/_api"
        try {
            try {
                $EnsureBody = ConvertTo-Json -Compress -InputObject @{ logonName = $LoginName }
                $EnsuredUser = New-GraphPostRequest -uri "$BaseUri/web/ensureuser" -tenantid $TenantFilter -scope $Scope -type POST -body $EnsureBody -contentType 'application/json;odata=nometadata' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
            } catch {
                throw "could not resolve the user (ensureuser): $($_.Exception.Message)"
            }
            if (-not $EnsuredUser.Id) { throw 'could not resolve the user on the site.' }
            if ($EnsuredUser.IsSiteAdmin) {
                throw 'user is a site collection admin; remove their admin permission first (Remove Site Admin action).'
            }
            try {
                $null = New-GraphPostRequest -uri "$BaseUri/web/siteusers/removebyid($($EnsuredUser.Id))" -tenantid $TenantFilter -scope $Scope -type POST -body '{}' -contentType 'application/json;odata=nometadata' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
            } catch {
                throw "removal failed: $($_.Exception.Message)"
            }
            $Succeeded.Add($SiteUrl)
        } catch {
            $Failed.Add("$($SiteUrl): $($_.Exception.Message)")
        }
    }

    return [PSCustomObject]@{
        Succeeded = @($Succeeded)
        Failed    = @($Failed)
    }
}
