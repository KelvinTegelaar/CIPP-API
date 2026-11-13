function Invoke-ListAppSignInActivity {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.Read
    .DESCRIPTION
        Returns when the tenant's apps and their credentials last signed in, from the CIPP DB caches of the Entra
        sign-in activity reports (Entra ID P1), for the app lists to show next to each app. apps holds one entry
        per app that signed in, by appId: its last sign-in of any kind, delegated and app-only. credentials holds
        one entry per secret or certificate that signed in, by keyId. An app or credential missing from a list
        that was collected has no sign-in recorded. Each list says whether and when it was collected: measure
        idle time from then, not from now, so a collection that stopped running never makes an app look idle.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Select a single tenant' } })
    }

    # Rows of a cache type and when it was collected; Collected is $false when it never was.
    function Get-CachedRows {
        param($Type, [string[]]$Fields)
        $Rows = [System.Collections.Generic.List[object]]::new()
        $Count = $null
        foreach ($Item in @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type $Type)) {
            if ($Item.RowKey -eq "$Type-Count") { $Count = $Item } else { $Rows.Add($Item) }
        }
        @{
            Collected   = [bool]($Count -or $Rows.Count -gt 0)
            CollectedAt = $Count.Timestamp
            Rows        = if ($Rows.Count -gt 0) { @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Type -Rows $Rows.ToArray() -Fields $Fields) } else { @() }
        }
    }

    try {
        $Apps = Get-CachedRows -Type 'ServicePrincipalSignInActivities' -Fields 'appId', 'lastSignInActivity', 'delegatedClientSignInActivity', 'applicationAuthenticationClientSignInActivity'
        $Credentials = Get-CachedRows -Type 'AppCredentialSignInActivities' -Fields 'keyId', 'appId', 'credentialOrigin', 'signInActivity'

        $Body = @{
            Results = [PSCustomObject]@{
                appsCollected          = $Apps.Collected
                appsCollectedAt        = $Apps.CollectedAt
                apps                   = @(foreach ($Row in $Apps.Rows) {
                        if (-not $Row.appId) { continue }
                        [PSCustomObject]@{
                            appId              = [string]$Row.appId
                            lastSignInDateTime = $Row.lastSignInActivity.lastSignInDateTime
                            lastDelegated      = $Row.delegatedClientSignInActivity.lastSignInDateTime
                            lastAppOnly        = $Row.applicationAuthenticationClientSignInActivity.lastSignInDateTime
                        }
                    })
                credentialsCollected   = $Credentials.Collected
                credentialsCollectedAt = $Credentials.CollectedAt
                credentials            = @(foreach ($Row in $Credentials.Rows) {
                        if (-not $Row.keyId) { continue }
                        [PSCustomObject]@{
                            keyId              = [string]$Row.keyId
                            appId              = [string]$Row.appId
                            credentialOrigin   = [string]$Row.credentialOrigin
                            lastSignInDateTime = $Row.signInActivity.lastSignInDateTime
                        }
                    })
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to read app sign-in activity: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Results = "Failed to read app sign-in activity: $($ErrorMessage.NormalizedError)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
