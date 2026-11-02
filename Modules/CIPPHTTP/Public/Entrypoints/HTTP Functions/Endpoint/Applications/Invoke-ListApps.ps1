function Invoke-ListApps {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Application.Read
    .DESCRIPTION
        Lists Intune managed applications for a tenant. Supports UseReportDB=true query parameter to retrieve cached data from the reporting database for significantly better performance, especially when querying AllTenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    # Serve from the reporting database cache instead of live Graph. Much faster, especially for AllTenants.
    $UseReportDB = $Request.Query.UseReportDB -eq $true
    try {
        if ($TenantFilter -eq 'AllTenants' -or $UseReportDB) {
            try {
                # Return one page per request as { Results, Metadata } with a continuation token in Metadata.nextLink.
                if ($Request.Query.manualPagination -eq $true) {
                    # Cached rows per page, clamped between 250 and 10000. Defaults to 5000. Pages hold whole tenants.
                    $PageSize = $Request.Query.PageSize -as [int]
                    return ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::OK
                            # Continuation token from the previous page's Metadata.nextLink; opaque to callers.
                            Body       = Get-CIPPReportPage -TenantFilter $TenantFilter -Type 'IntuneApplications' -PageSize $PageSize -ContinuationToken $Request.Query.nextLink -Report { param($Tenant) Get-CIPPIntuneApplicationReport -TenantFilter $Tenant -ErrorAction Stop }
                        })
                }
                $GraphRequest = Get-CIPPIntuneApplicationReport -TenantFilter $TenantFilter -ErrorAction Stop
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                $StatusCode = [HttpStatusCode]::InternalServerError
                $GraphRequest = $_.Exception.Message
            }
            return ([HttpResponseContext]@{
                    StatusCode = $StatusCode
                    Body       = @($GraphRequest)
                })
        }

        # Use bulk requests to get groups and apps with assignments
        $BulkRequests = @(
            @{
                id     = 'Groups'
                method = 'GET'
                url    = '/groups?$top=999&$select=id,displayName'
            }
            @{
                id     = 'Apps'
                method = 'GET'
                url    = "/deviceAppManagement/mobileApps?`$top=999&`$expand=assignments&`$filter=(microsoft.graph.managedApp/appAvailability%20eq%20null%20or%20microsoft.graph.managedApp/appAvailability%20eq%20%27lineOfBusiness%27%20or%20isAssigned%20eq%20true)&`$orderby=displayName"
            }
        )

        $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter

        # Extract groups for resolving assignment names
        $Groups = ($BulkResults | Where-Object { $_.id -eq 'Groups' }).body.value
        $Apps = ($BulkResults | Where-Object { $_.id -eq 'Apps' }).body.value

        $GraphRequest = foreach ($App in $Apps) {
            # Process assignments
            $AppAssignment = [System.Collections.Generic.List[string]]::new()
            $AppExclude = [System.Collections.Generic.List[string]]::new()

            if ($App.assignments) {
                foreach ($Assignment in $App.assignments) {
                    $target = $Assignment.target
                    $intent = $Assignment.intent
                    $intentSuffix = if ($intent) { " ($intent)" } else { '' }

                    switch ($target.'@odata.type') {
                        '#microsoft.graph.allDevicesAssignmentTarget' { $AppAssignment.Add("All Devices$intentSuffix") }
                        '#microsoft.graph.allLicensedUsersAssignmentTarget' { $AppAssignment.Add("All Licensed Users$intentSuffix") }
                        '#microsoft.graph.groupAssignmentTarget' {
                            $groupName = ($Groups | Where-Object { $_.id -eq $target.groupId }).displayName
                            if ($groupName) { $AppAssignment.Add("$groupName$intentSuffix") }
                        }
                        '#microsoft.graph.exclusionGroupAssignmentTarget' {
                            $groupName = ($Groups | Where-Object { $_.id -eq $target.groupId }).displayName
                            if ($groupName) { $AppExclude.Add("$groupName$intentSuffix") }
                        }
                    }
                }
            }

            $App | Add-Member -NotePropertyMembers ([ordered]@{
                    AppAssignment = ($AppAssignment -join ', ')
                    AppExclude    = ($AppExclude -join ', ')
                }) -Force
            $App
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
        $GraphRequest = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
