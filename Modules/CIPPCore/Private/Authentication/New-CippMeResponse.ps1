function New-CippMeResponse {
    <#
    .SYNOPSIS
        Builds the /me HTTP response for the user branch of Test-CIPPAccess.

    .DESCRIPTION
        Extracted verbatim from Test-CIPPAccess. All request-scoped state arrives as
        parameters — including the impersonation marker — so nothing here depends on
        script scope crossing function boundaries.

    .PARAMETER User
        Resolved (possibly impersonated) client principal.

    .PARAMETER IPAllowed
        Result of the caller's IP-range check. /me is exempt from the IP throw but
        reports the denial in its body instead.

    .PARAMETER IPAddress
        Parsed request IP; only referenced in the IP-denial message.

    .PARAMETER Impersonation
        The active impersonation object ($null when not impersonating).

    .PARAMETER AccessTimings
        The caller's profiling hashtable; mutated by reference to record timings.

    .FUNCTIONALITY
        Internal
    #>
    param(
        $User,
        $IPAllowed,
        $IPAddress,
        $Impersonation,
        $AccessTimings
    )

    if (!$User.userRoles) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = (
                    @{
                        'clientPrincipal' = $null
                        'permissions'     = @()
                    } | ConvertTo-Json -Depth 5)
            })
    }

    if (!$IPAllowed) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = (
                    @{
                        'clientPrincipal' = $null
                        'permissions'     = @()
                        'message'         = "Your IP address ($IPAddress) is not in the allowed range for your role(s)"
                    } | ConvertTo-Json -Depth 5)
            })
    }

    $swPermsMe = [System.Diagnostics.Stopwatch]::StartNew()
    $Permissions = Get-CippAllowedPermissions -UserRoles $User.userRoles
    $swPermsMe.Stop()
    $AccessTimings['GetPermissions(me)'] = $swPermsMe.Elapsed.TotalMilliseconds

    # Include SSO migration status for admins with AppSettings permissions
    $MeResponse = @{
        'clientPrincipal' = $User
        'permissions'     = @($Permissions)
    }
    if ($Impersonation) {
        # The frontend banner needs these to render the exit affordance even when
        # the impersonated role has almost no permissions.
        $MeResponse['impersonating'] = $Impersonation.Impersonating
        $MeResponse['realUserRoles'] = @($Impersonation.RealRoles)
    }

    # Hosted payment status checks — shown to all users (no permission gating)
    if ($env:cipp_hosted_subscription_ended) {
        $MeResponse['hostedSubscriptionEnded'] = $true
    }
    if ($env:cipp_hosted_failed_payments) {
        $MeResponse['hostedFailedPayments'] = $true
    }
    # CyberDrain-hosted instance (CIPP_HOSTED is set by the hosted deployment templates).
    # Lets the frontend point at the management portal for anything the instance's own
    # identity cannot do, such as custom domains on the shared App Service plan.
    $MeResponse['hosted'] = $env:CIPP_HOSTED -eq 'true'
    # CIPP-NG (container web app on an App Service plan) versus a legacy function app plus
    # static web app - the backend page shows different resources for each.
    $MeResponse['ng'] = $env:CIPPNG -eq 'true'

    $CanManageAppSettings = $Permissions -contains 'CIPP.AppSettings.ReadWrite'
    $HasAnyPermission = ($Permissions | Measure-Object).Count -gt 0

    # Initial setup state: real (non-placeholder) SAM credentials loaded in this
    # worker. Placeholder set matches Get-CIPPAuthentication/Initialize-CIPPAuth.
    # The frontend blocks the whole UI behind the setup wizard until complete;
    # samAppPresent distinguishes "no app registration at all" from "app exists
    # but the refresh token is missing" so the wizard can offer a token reset.
    $PlaceholderPattern = '^(LongApplicationId|AppSecret|RefreshToken|tenantId)$'
    $TestSamCredentials = {
        $HasAppId = [bool]($env:ApplicationID -and $env:ApplicationID -notmatch $PlaceholderPattern -and
            $env:TenantID -and $env:TenantID -notmatch $PlaceholderPattern)
        $HasRefreshToken = [bool]($env:RefreshToken -and $env:RefreshToken -notmatch $PlaceholderPattern)
        @{ HasAppId = $HasAppId; Complete = ($HasAppId -and $HasRefreshToken) }
    }
    $SamState = & $TestSamCredentials
    if (-not $SamState.Complete) {
        # Env vars are per-worker and loaded at warmup, so setup completed on
        # another worker leaves this one stale. Reload at most once per 30s per
        # worker, tracked in an env var because runspaces don't share script
        # scope, so an unconfigured instance doesn't hit storage on every poll.
        $NowUnix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $LastAttempt = [int64]0
        $null = [int64]::TryParse($env:CippMeAuthReloadAt, [ref]$LastAttempt)
        if (($NowUnix - $LastAttempt) -ge 30) {
            $env:CippMeAuthReloadAt = [string]$NowUnix
            $null = Get-CIPPAuthentication
            $SamState = & $TestSamCredentials
        }
    }
    $MeResponse['initialSetupComplete'] = $SamState.Complete
    $MeResponse['samAppPresent'] = $SamState.HasAppId

    # Forced SSO migration: non-dismissible prompt when migration env var is set.
    # Suppressed until initial setup (SAM app) is complete — the setup wizard has
    # to run first, and ExecSSOSetup needs the SAM app to create the CIPP-SSO
    # registration.
    $InitialSetupComplete = $SamState.Complete
    if ($env:CIPP_SSO_MIGRATION_APPID -and $CanManageAppSettings -and $InitialSetupComplete) {
        $MeResponse['forceSsoMigration'] = @{
            appId  = $env:CIPP_SSO_MIGRATION_APPID
            status = 'pending'
        }
    }

    if ($env:CIPPNG -ne 'true' -and $HasAnyPermission) {
        try {
            $SSOTable = Get-CIPPTable -tablename 'SSOMigration'
            $SSOMigration = Get-CIPPAzDataTableEntity @SSOTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'MigrationConfig'" -ErrorAction SilentlyContinue
            if ($SSOMigration) {
                $MeResponse['ssoMigration'] = @{
                    status      = $SSOMigration.Status
                    appId       = $SSOMigration.AppId
                    multiTenant = [bool]($SSOMigration.MultiTenant -eq 'true' -or $SSOMigration.MultiTenant -eq 'True')
                }
            } else {
                $MeResponse['ssoMigration'] = @{ status = 'none' }
            }
        } catch {
            $MeResponse['ssoMigration'] = @{ status = 'none' }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ($MeResponse | ConvertTo-Json -Depth 5)
        })
}
