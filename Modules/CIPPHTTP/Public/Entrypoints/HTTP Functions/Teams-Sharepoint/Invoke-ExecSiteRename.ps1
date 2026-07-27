function Invoke-ExecSiteRename {
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
    $TenantFilter = $Request.Body.tenantFilter
    $SiteId = $Request.Body.SiteId
    $SiteUrl = $Request.Body.SiteUrl
    $DisplayName = $Request.Body.DisplayName
    $NewTitle = $Request.Body.NewTitle
    $NewUrl = $Request.Body.NewUrl
    $SiteLabel = if ($DisplayName) { $DisplayName } else { $SiteUrl }

    try {
        if (-not $TenantFilter) { throw 'tenantFilter is required' }
        if (-not $NewTitle -and -not $NewUrl) { throw 'Provide NewTitle, NewUrl, or both' }

        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $ExtraHeaders = @{
            'accept'        = 'application/json'
            'content-type'  = 'application/json'
            'odata-version' = '4.0'
        }
        $Messages = [System.Collections.Generic.List[string]]::new()

        if ($NewTitle) {
            if (-not $SiteId) { throw 'SiteId is required to change the title' }
            $PatchBody = @{ Title = $NewTitle } | ConvertTo-Json -Compress
            $null = New-GraphPOSTRequest `
                -scope "$($SharePointInfo.AdminUrl)/.default" `
                -uri "$($SharePointInfo.AdminUrl)/_api/SPO.Tenant/sites('$SiteId')" `
                -body $PatchBody `
                -tenantid $TenantFilter `
                -type PATCH `
                -AddedHeaders $ExtraHeaders
            $Messages.Add("Title changed to '$NewTitle'. For group-connected sites the site name follows the Microsoft 365 group; rename the group to keep them in sync.")
        }

        if ($NewUrl) {
            if (-not $SiteUrl) { throw 'SiteUrl is required to change the URL' }
            $RenameBody = @{
                SourceSiteUrl = $SiteUrl
                TargetSiteUrl = $NewUrl
            } | ConvertTo-Json -Compress
            $RenameJob = New-GraphPOSTRequest `
                -scope "$($SharePointInfo.AdminUrl)/.default" `
                -uri "$($SharePointInfo.AdminUrl)/_api/SiteRenameJobs?api-version=1.4.7" `
                -body $RenameBody `
                -tenantid $TenantFilter `
                -type POST `
                -AddedHeaders $ExtraHeaders
            $JobState = $RenameJob.JobState
            $Messages.Add("URL change to '$NewUrl' queued (job state: $JobState). SharePoint renames the site in the background; a redirect is created at the old URL. Large sites can take a while.")
        }

        $Results = "Site '$SiteLabel': $($Messages -join ' ')"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info

        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = $Results }
        })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $ErrorText = $ErrorMessage.NormalizedError
        if ($ErrorText -match 'already exists|SiteMoveInProgress|rename job') {
            $ErrorText = "A site already exists at the target URL or a rename is already in progress. Original error: $ErrorText"
        }
        $Results = "Failed to rename site '$SiteLabel'. Error: $ErrorText"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage

        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{ Results = $Results }
        })
    }
}
