function Invoke-ListGuestUsers {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    .SYNOPSIS
        List guest users with lifecycle status
    .DESCRIPTION
        Lists all guest accounts in a tenant with a computed lifecycle status (Active, Pending Acceptance, Stale, Never Signed In or Disabled) based on the invitation state and sign-in activity. Supports UseReportDB=true to serve cached data from the reporting database; AllTenants always uses the cache. When manualPagination is set on a cached read, one page is returned per request as { Results, Metadata } with a continuation token in Metadata.nextLink.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # The tenant to list guest users for, or AllTenants for every tenant (served from the cache)
    $TenantFilter = $Request.Query.tenantFilter
    # Days without any sign-in before an enabled guest is considered stale. Defaults to 90.
    $StaleDays = $Request.Query.staleDays ? [int]$Request.Query.staleDays : 90
    # Serve from the reporting database cache instead of live Graph. AllTenants always uses the cache.
    $UseReportDB = $Request.Query.UseReportDB -eq $true
    # Return one page per request as { Results, Metadata } with a continuation token in Metadata.nextLink; cached reads only.
    $ManualPagination = $Request.Query.manualPagination -and [System.Convert]::ToBoolean($Request.Query.manualPagination)
    $NextToken = $null

    try {
        if ($TenantFilter -eq 'AllTenants' -or $UseReportDB) {
            # Cached rows carry a per-row signInLogsCapable stamp written by the cache job,
            # so sign-in availability is judged per row below.
            $SignInLogsCapable = $null
            if ($ManualPagination) {
                # Rows per page, clamped between 250 and 10000. Defaults to 5000.
                $PageSize = 5000
                if ($Request.Query.PageSize -as [int]) {
                    $PageSize = [Math]::Min([Math]::Max([int]$Request.Query.PageSize, 250), 10000)
                }
                # Continuation token from the previous page's Metadata.nextLink; opaque to callers.
                $Page = Get-CIPPGuestUsersReport -TenantFilter $TenantFilter -PageSize $PageSize -ContinuationToken $Request.Query.nextLink
                $GuestUsers = $Page.Items
                $NextToken = $Page.NextToken
            } else {
                $GuestUsers = Get-CIPPGuestUsersReport -TenantFilter $TenantFilter
            }
        } else {
            # signInActivity can only be requested on tenants with an Entra ID P1 license - Graph
            # rejects the whole query on unlicensed tenants, so fall back to listing without
            # sign-in data there and compute status from the invitation state alone.
            $SignInLogsCapable = Test-CIPPStandardLicense -StandardName 'GuestLifecycle' -TenantFilter $TenantFilter -Preset Entra -SkipLog

            $SelectFields = @(
                'id', 'displayName', 'mail', 'userPrincipalName', 'createdDateTime',
                'accountEnabled', 'externalUserState', 'externalUserStateChangeDateTime'
            )
            if ($SignInLogsCapable) { $SelectFields += 'signInActivity' }
            # Graph caps the page size lower when signInActivity is selected
            $Top = $SignInLogsCapable ? 500 : 999
            $Uri = "https://graph.microsoft.com/beta/users?`$filter=userType eq 'Guest'&`$select=$($SelectFields -join ',')&`$count=true&`$top=$Top"
            $GuestUsers = New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -ComplexFilter
        }

        $Now = Get-Date
        $GraphRequest = foreach ($Guest in $GuestUsers) {
            $RowCapable = ($null -eq $SignInLogsCapable) ? ($Guest.signInLogsCapable -eq $true) : $SignInLogsCapable

            # Last sign-in is the most recent of the three signInActivity fields.
            # lastSuccessfulSignInDateTime can run ahead of the other two, so leaving it
            # out would report recently-active guests as stale.
            $LastSignIn = $null
            $Candidates = @(
                $Guest.signInActivity.lastSignInDateTime
                $Guest.signInActivity.lastNonInteractiveSignInDateTime
                $Guest.signInActivity.lastSuccessfulSignInDateTime
            )
            foreach ($Candidate in $Candidates) {
                if ($Candidate -and (-not $LastSignIn -or [datetime]$Candidate -gt [datetime]$LastSignIn)) {
                    $LastSignIn = $Candidate
                }
            }
            $DaysSinceSignIn = $LastSignIn ? [math]::Round(($Now - [datetime]$LastSignIn).TotalDays) : $null

            $Status = if ($Guest.accountEnabled -eq $false) {
                'Disabled'
            } elseif ($Guest.externalUserState -eq 'PendingAcceptance') {
                'Pending Acceptance'
            } elseif (-not $RowCapable) {
                'Unknown'
            } elseif (-not $LastSignIn) {
                'Never Signed In'
            } elseif ($DaysSinceSignIn -ge $StaleDays) {
                'Stale'
            } else {
                'Active'
            }

            $Row = [PSCustomObject]@{
                id                               = $Guest.id
                displayName                      = $Guest.displayName
                mail                             = $Guest.mail
                userPrincipalName                = $Guest.userPrincipalName
                sourceDomain                     = $Guest.mail ? ($Guest.mail -split '@')[1] : $null
                status                           = $Status
                accountEnabled                   = $Guest.accountEnabled
                externalUserState                = $Guest.externalUserState
                externalUserStateChangeDateTime  = $Guest.externalUserStateChangeDateTime
                createdDateTime                  = $Guest.createdDateTime
                lastSignInDateTime               = $LastSignIn
                lastInteractiveSignInDateTime    = $Guest.signInActivity.lastSignInDateTime
                lastNonInteractiveSignInDateTime = $Guest.signInActivity.lastNonInteractiveSignInDateTime
                lastSuccessfulSignInDateTime     = $Guest.signInActivity.lastSuccessfulSignInDateTime
                daysSinceSignIn                  = $DaysSinceSignIn
                sponsors                         = $Guest.sponsors ? (@($Guest.sponsors | ForEach-Object { $_.displayName ?? $_.userPrincipalName }) -join ', ') : $null
            }
            if ($null -ne $Guest.CacheTimestamp) {
                $Row | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $Guest.CacheTimestamp
            }
            if ($Guest.Tenant) {
                $Row | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Guest.Tenant
            }
            $Row
        }
        $StatusCode = [System.Net.HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to list guest users: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [System.Net.HttpStatusCode]::InternalServerError
        $GraphRequest = @{ Error = $ErrorMessage.NormalizedError }
    }

    # Paged cached reads return { Results, Metadata }; everything else keeps the legacy bare array.
    if ($ManualPagination -and ($TenantFilter -eq 'AllTenants' -or $UseReportDB) -and $StatusCode -eq [System.Net.HttpStatusCode]::OK) {
        $Metadata = @{}
        if ($NextToken) { $Metadata.nextLink = $NextToken }
        return ([HttpResponseContext]@{
                StatusCode = $StatusCode
                Body       = [PSCustomObject]@{
                    Results  = @($GraphRequest)
                    Metadata = $Metadata
                }
            })
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })
}
