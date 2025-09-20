using namespace System.Net

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
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $SiteId = $Request.Body.SiteId

    try {
        # Validate required parameters
        if (-not $SiteId) {
            throw "SiteId is required"
        }
        if (-not $TenantFilter) {
            throw "TenantFilter is required"
        }

        # Validate SiteId format (GUID)
        if ($SiteId -notmatch '^(\{)?[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(\})?$') {
            throw "SiteId must be a valid GUID"
        }

        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter

        # Get site information using SharePoint admin API
        $SiteInfoUri = "$($SharePointInfo.AdminUrl)/_api/SPO.Tenant/sites('$SiteId')"

        # Add the headers that SharePoint REST API expects
        $ExtraHeaders = @{
            'accept' = 'application/json'
            'content-type' = 'application/json'
            'odata-version' = '4.0'
        }

        $SiteInfo = New-GraphGETRequest -scope "$($SharePointInfo.AdminUrl)/.default" -uri $SiteInfoUri -tenantid $TenantFilter -extraHeaders $ExtraHeaders

        if (-not $SiteInfo) {
            throw "Could not retrieve site information from SharePoint Admin API"
        }

        # Determine if site is group-connected based on GroupId
        $IsGroupConnected = $SiteInfo.GroupId -and $SiteInfo.GroupId -ne "00000000-0000-0000-0000-000000000000"

        if ($IsGroupConnected) {
            # Use GroupSiteManager/Delete for group-connected sites
            $body = @{
                siteUrl = $SiteInfo.Url
            }
            $DeleteUri = "$($SharePointInfo.AdminUrl)/_api/GroupSiteManager/Delete"
        } else {
            # Use SPSiteManager/delete for regular sites
            $body = @{
                siteId = $SiteId
            }
            $DeleteUri = "$($SharePointInfo.AdminUrl)/_api/SPSiteManager/delete"
        }

        # Execute the deletion
        $DeleteResult = New-GraphPOSTRequest -scope "$($SharePointInfo.AdminUrl)/.default" -uri $DeleteUri -body (ConvertTo-Json -Depth 10 -InputObject $body) -tenantid $TenantFilter -extraHeaders $ExtraHeaders

        $SiteTypeMsg = if ($IsGroupConnected) { "group-connected" } else { "regular" }
        $Results = "Successfully initiated deletion of $SiteTypeMsg SharePoint site with ID $SiteId, this process can take some time to complete in the background"

        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to delete SharePoint site with ID $SiteId. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = @{ 'Results' = $Results }
    })
}
