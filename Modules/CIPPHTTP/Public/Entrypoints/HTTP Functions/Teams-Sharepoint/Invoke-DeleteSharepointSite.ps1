function Invoke-DeleteSharepointSite {
    <#
    .FUNCTIONALITY
     Entrypoint
    .ROLE
     Sharepoint.Site.ReadWrite
     #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $SiteId = $Request.Body.SiteId

    try {
        # Validate required parameters
        if (-not $SiteId) {
            throw 'SiteId is required'
        }
        if (-not $TenantFilter) {
            throw 'TenantFilter is required'
        }

        # Validate SiteId format (GUID)
        if ($SiteId -notmatch '^(\{)?[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(\})?$') {
            throw 'SiteId must be a valid GUID'
        }

        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter

        # Get site information using SharePoint admin API
        $SiteInfoUri = "$($SharePointInfo.AdminUrl)/_api/SPO.Tenant/sites('$SiteId')"

        # The SPO.Tenant vroute GET needs odata-version 4.0; the manager POST endpoints must
        # NOT receive it - sending it flips them onto a pipeline that rejects the call with
        # 'Elevated context should be used only to create service asserted level PoP'.
        $GetHeaders = @{
            'accept'        = 'application/json'
            'odata-version' = '4.0'
        }
        $PostHeaders = @{
            'accept' = 'application/json'
        }

        try {
            $SiteInfo = New-GraphGETRequest -scope "$($SharePointInfo.AdminUrl)/.default" -uri $SiteInfoUri -tenantid $TenantFilter -extraHeaders $GetHeaders -UseCertificate -AsApp $true
        } catch {
            throw "Could not retrieve site information from the SharePoint Admin API: $($_.Exception.Message)"
        }

        if (-not $SiteInfo) {
            throw 'Could not retrieve site information from SharePoint Admin API'
        }

        # Determine if site is group-connected based on GroupId
        $IsGroupConnected = $SiteInfo.GroupId -and $SiteInfo.GroupId -ne '00000000-0000-0000-0000-000000000000'

        if ($IsGroupConnected) {
            # Group-connected sites: GroupSiteManager/Delete soft-deletes the backing M365
            # group (and Team) together with the site and registers it in the SPO deleted
            # sites list. Runs with the delegated token (the CIPP service account is a
            # SharePoint admin); see the header note above for why odata-version is omitted.
            $body = @{
                siteUrl = $SiteInfo.Url
            }
            try {
                $null = New-GraphPOSTRequest -scope "$($SharePointInfo.AdminUrl)/.default" -uri "$($SharePointInfo.AdminUrl)/_api/GroupSiteManager/Delete" -body (ConvertTo-Json -Depth 10 -InputObject $body) -tenantid $TenantFilter -contentType 'application/json' -AddedHeaders $PostHeaders
            } catch {
                throw "Site deletion request failed (GroupSiteManager/Delete): $($_.Exception.Message)"
            }
            $Results = "Successfully initiated deletion of group-connected SharePoint site $($SiteInfo.Url); the backing M365 group (and Team, if any) is deleted with it. This can take some time to complete in the background."
        } else {
            # Regular sites: SPSiteManager/delete denies delegated tokens (even with a
            # certificate assertion) with E_ACCESSDENIED - it requires app-only cert auth.
            $body = @{
                siteId = $SiteId
            }
            try {
                $null = New-GraphPOSTRequest -scope "$($SharePointInfo.AdminUrl)/.default" -uri "$($SharePointInfo.AdminUrl)/_api/SPSiteManager/delete" -body (ConvertTo-Json -Depth 10 -InputObject $body) -tenantid $TenantFilter -contentType 'application/json' -AddedHeaders $PostHeaders -UseCertificate -AsApp $true
            } catch {
                throw "Site deletion request failed (SPSiteManager/delete): $($_.Exception.Message)"
            }
            $Results = "Successfully initiated deletion of SharePoint site with ID $SiteId, this process can take some time to complete in the background"
        }

        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to delete SharePoint site with ID $SiteId. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })
}
