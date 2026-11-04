function Invoke-ListSharedMailboxAccountEnabled {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Lists shared mailboxes that have direct sign-in enabled (account not disabled), which is a security concern.
        Supports UseReportDB=true to read cached data from the reporting database (required for AllTenants).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter
    # Serve from the reporting database cache instead of live Graph. Much faster, especially for AllTenants.
    $UseReportDB = $Request.Query.UseReportDB -eq $true
    # Get Shared Mailbox Stuff
    try {
        # If UseReportDB is specified, retrieve from the report database (cached Mailboxes + Users join)
        if ($UseReportDB) {
            try {
                # Return one page per request as { Results, Metadata } with a continuation token in Metadata.nextLink.
                if ($Request.Query.manualPagination -eq $true) {
                    # Cached rows per page, clamped between 250 and 10000. Defaults to 5000. Pages hold whole tenants.
                    $PageSize = $Request.Query.PageSize -as [int]
                    return ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::OK
                            # Continuation token from the previous page's Metadata.nextLink; opaque to callers.
                            Body       = Get-CIPPReportPage -TenantFilter $TenantFilter -Type 'Mailboxes' -PageSize $PageSize -ContinuationToken $Request.Query.nextLink -Report { param($Tenant) Get-CIPPSharedMailboxAccountEnabledReport -TenantFilter $Tenant -ErrorAction Stop }
                        })
                }
                $GraphRequest = Get-CIPPSharedMailboxAccountEnabledReport -TenantFilter $TenantFilter -ErrorAction Stop
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

        $SharedMailboxList = (New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($TenantFilter)/Mailbox?`$filter=RecipientTypeDetails eq 'SharedMailbox'" -Tenantid $TenantFilter -scope ExchangeOnline)
        $Select = 'id,userPrincipalName,accountEnabled,displayName,givenName,surname,onPremisesSyncEnabled,assignedLicenses'
        # signInActivity needs Entra P1, Graph rejects the whole request without it
        if (Test-CIPPStandardLicense -StandardName 'UserSignInLogsCapable' -TenantFilter $TenantFilter -Preset Entra -SkipLog) {
            $Select = "$Select,signInActivity"
        }
        $AllUsersInfo = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=500&`$select=$Select" -tenantid $TenantFilter
        $SharedMailboxDetails = foreach ($SharedMailbox in $SharedMailboxList) {
            # Match the User
            $User = $AllUsersInfo | Where-Object { $_.userPrincipalName -eq $SharedMailbox.userPrincipalName } | Select-Object -First 1

            if ($User.accountEnabled) {
                # Return all shared mailboxes with license information
                [PSCustomObject]@{
                    UserPrincipalName     = $User.userPrincipalName
                    displayName           = $User.displayName
                    givenName             = $User.givenName
                    surname               = $User.surname
                    accountEnabled        = $User.accountEnabled
                    assignedLicenses      = $User.assignedLicenses
                    id                    = $User.id
                    onPremisesSyncEnabled = $User.onPremisesSyncEnabled
                    lastSuccessfulSignInDateTime = $User.signInActivity.lastSuccessfulSignInDateTime
                }
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Shared Mailbox List on $($TenantFilter). Error: $($_.exception.message)" -sev 'Error'
    }
    $GraphRequest = $SharedMailboxDetails
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
