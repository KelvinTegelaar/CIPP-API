function Invoke-ListmailboxPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Lists mailbox permissions (Full Access, Send As, Send on Behalf) for a tenant. Supports UseReportDB=true query parameter to retrieve cached data from the reporting database for significantly better performance, especially when querying AllTenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $UserID = $Request.Query.userId
    # Serve from the reporting database cache instead of live Graph. Much faster, especially for AllTenants.
    $UseReportDB = $Request.Query.UseReportDB -eq $true
    $ByUser = $Request.Query.ByUser
    $User = $Request.Query.User

    try {
        # If UseReportDB is specified and no specific UserID, retrieve from report database
        if ($UseReportDB -and -not $UserID) {

            # Call the report function with proper parameters
            $ReportParams = @{
                TenantFilter = $TenantFilter
            }
            if ($ByUser -eq 'true') {
                $ReportParams.ByUser = $true
            }
            try {
                # Return one page per request as { Results, Metadata } with a continuation token in Metadata.nextLink.
                if ($Request.Query.manualPagination -eq $true) {
                    # Cached rows per page, clamped between 250 and 10000. Defaults to 5000. Pages hold whole tenants.
                    $PageSize = $Request.Query.PageSize -as [int]
                    return ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::OK
                            # Continuation token from the previous page's Metadata.nextLink; opaque to callers.
                            Body       = Get-CIPPReportPage -TenantFilter $TenantFilter -Type 'Mailboxes' -PageSize $PageSize -ContinuationToken $Request.Query.nextLink -Report {
                                param($Tenant)
                                $Rows = Get-CIPPMailboxPermissionReport -TenantFilter $Tenant -ByUser:($ByUser -eq 'true')
                                if ($User -and $ByUser -eq 'true') { $Rows.Where({ $_.User -eq $User }) } else { $Rows }
                            }
                        })
                }
                $GraphRequest = Get-CIPPMailboxPermissionReport @ReportParams
                if ($User -and $ByUser -eq 'true') {
                    # Only the user-grouped report has a top-level User property; in the
                    # mailbox-grouped shape this filter would empty the whole result set.
                    $GraphRequest = @($GraphRequest | Where-Object { $_.User -eq $User })
                }
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

        # Original live query logic for specific user
        $Requests = @(
            @{
                CmdletInput = @{
                    CmdletName = 'Get-Mailbox'
                    Parameters = @{ Identity = $UserID }
                }
            }
            @{
                CmdletInput = @{
                    CmdletName = 'Get-MailboxPermission'
                    Parameters = @{ Identity = $UserID }
                }
            }
            @{
                CmdletInput = @{
                    CmdletName = 'Get-RecipientPermission'
                    Parameters = @{ Identity = $UserID }
                }
            }
        )

        $Results = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray $Requests
        $GraphRequest = foreach ($Perm in $Results) {
            if ($Perm.Trustee) {
                $Perm | Where-Object Trustee | ForEach-Object { [PSCustomObject]@{
                        User        = $_.Trustee
                        Permissions = $_.accessRights
                    }
                }
            }
            if ($Perm.AccessRights) {
                $Perm | Where-Object User | ForEach-Object { [PSCustomObject]@{
                        User        = $_.User
                        Permissions = $_.AccessRights -join ', '
                    }
                }
            }
            if ($Perm.GrantSendonBehalfTo) {
                $Perm.GrantSendonBehalfTo | ForEach-Object { [PSCustomObject]@{
                        User        = $_
                        Permissions = 'SendOnBehalf'
                    }
                }
            }
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
