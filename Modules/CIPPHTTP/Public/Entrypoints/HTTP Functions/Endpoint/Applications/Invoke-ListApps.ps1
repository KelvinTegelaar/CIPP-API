function Invoke-ListApps {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Application.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    try {
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
                            if ($groupName) { $AppExclude.Add($groupName) }
                        }
                    }
                }
            }

            $App | Add-Member -NotePropertyName 'AppAssignment' -NotePropertyValue ($AppAssignment -join ', ') -Force
            $App | Add-Member -NotePropertyName 'AppExclude' -NotePropertyValue ($AppExclude -join ', ') -Force
            $App
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
