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
                    url    = "/users/`$count"
                    headers = @{
                        'ConsistencyLevel' = 'eventual'
                    }
                }
                @{
                    id     = 'LicUsers'
                    method = 'GET'
                    url    = "/users/`$count?`$top=1&`$filter=assignedLicenses/`$count ne 0"
                    headers = @{
                        'ConsistencyLevel' = 'eventual'
                    }
                }
                @{
                    id     = 'GAs'
                    method = 'GET'
                    url    = "/directoryRoles/roleTemplateId=62e90394-69f5-4237-9190-012177145e10/members/`$count"
                    headers = @{
                        'ConsistencyLevel' = 'eventual'
                    }
                }
                @{
                    id     = 'Guests'
                    method = 'GET'
                    url    = "/users/`$count?`$top=1&`$filter=userType eq 'Guest'"
                    headers = @{
                        'ConsistencyLevel' = 'eventual'
                    }
                }
            )

            # Execute bulk request
            $BulkResults = New-GraphBulkRequest -Requests @($BulkRequests) -noPaginateIds @('LicUsers') -tenantid $TenantFilter @('Users', 'LicUsers', 'GAs', 'Guests')

            # Check if any requests failed
            $FailedRequests = $BulkResults | Where-Object { $_.status -ne 200 }

            if ($FailedRequests) {
                # If any requests failed, return an error response
                $FailedIds = ($FailedRequests | ForEach-Object { $_.id }) -join ', '
                $ErrorMessage = "Failed to retrieve counts for: $FailedIds"

                return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::InternalServerError
                    Body       = @{
                        Error   = $ErrorMessage
                        Details = $FailedRequests
                    }
                })
            }

            # All requests succeeded, extract the counts
            $BulkResults | ForEach-Object {
                $UsersCount = $_.body

                switch ($_.id) {
                    'Users' { $Users = $UsersCount }
                    'LicUsers' { $LicUsers = $UsersCount }
                    'GAs' { $GAs = $UsersCount }
                    'Guests' { $Guests = $UsersCount }
                }
            }

        } catch {
            # Return error status on exception
            return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{
                    Error = "Failed to retrieve user counts: $($_.Exception.Message)"
                }
            })
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
