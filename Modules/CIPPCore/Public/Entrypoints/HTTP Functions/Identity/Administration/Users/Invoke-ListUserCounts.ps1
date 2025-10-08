Function Invoke-ListUserCounts {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    if ($Request.Query.TenantFilter -eq 'AllTenants') {
        $Users = 'Not Supported'
        $LicUsers = 'Not Supported'
        $GAs = 'Not Supported'
        $Guests = 'Not Supported'
    } else {
        try {
            # Build bulk requests array
            [System.Collections.Generic.List[PSCustomObject]]$BulkRequests = @(
                @{
                    id     = 'Users'
                    method = 'GET'
                    url    = "/users?`$count=true&`$top=1"
                    headers = @{
                        'ConsistencyLevel' = 'eventual'
                    }
                }
                @{
                    id     = 'LicUsers'
                    method = 'GET'
                    url    = "/users?`$count=true&`$top=1&`$filter=assignedLicenses/`$count ne 0"
                    headers = @{
                        'ConsistencyLevel' = 'eventual'
                    }
                }
                @{
                    id     = 'GAs'
                    method = 'GET'
                    url    = "/directoryRoles/roleTemplateId=62e90394-69f5-4237-9190-012177145e10/members?`$count=true"
                    headers = @{
                        'ConsistencyLevel' = 'eventual'
                    }
                }
                @{
                    id     = 'Guests'
                    method = 'GET'
                    url    = "/users?`$count=true&`$top=1&`$filter=userType eq 'Guest'"
                    headers = @{
                        'ConsistencyLevel' = 'eventual'
                    }
                }
            )

            # Execute bulk request
            $BulkResults = New-GraphBulkRequest -Requests @($BulkRequests) -tenantid $TenantFilter @('Users', 'LicUsers', 'GAs', 'Guests')

            $BulkResults | ForEach-Object {
                $Count = if ($_.status -eq 200) {
                    $_.body.'@odata.count'
                } else {
                    'Not available'
                }

                switch ($_.id) {
                    'Users' { $Users = $Count }
                    'LicUsers' { $LicUsers = $Count }
                    'GAs' { $GAs = $Count }
                    'Guests' { $Guests = $Count }
                }
            }

        } catch {
            $Users = 'Not available'
            $LicUsers = 'Not available'
            $GAs = 'Not available'
            $Guests = 'Not available'
        }
    }

    $Counts = @{
        Users    = $Users
        LicUsers = $LicUsers
        Gas      = $GAs
        Guests   = $Guests
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Counts
        })

}
