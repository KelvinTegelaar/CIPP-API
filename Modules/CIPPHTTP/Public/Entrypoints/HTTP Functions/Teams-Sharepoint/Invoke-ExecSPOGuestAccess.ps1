function Invoke-ExecSPOGuestAccess {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .DESCRIPTION
        Manages a guest's access on a single SharePoint site via the site-level guest
        expiration feature (SP.User.Expiration):
          Extend - sets Expiration to now + Days (1-90, default 90)
          Expire - expires the guest's access on this site immediately
        The Entra guest account and other site memberships are not touched. Graph has no
        equivalent, so this uses SharePoint REST with the SAM certificate (app-only).

        Body:
          tenantFilter - tenant
          SiteUrl      - full site URL
          SiteUserId   - SharePoint site user ID (SiteAccess[].SiteUserId from ListSharePointExternalUsers)
          Action       - 'Extend' or 'Expire'
          Days         - Extend only; days from now, 1-90, default 90
          DisplayName  - optional, for logging
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $SiteUrl = ([string]$Request.Body.SiteUrl).TrimEnd('/')
    $SiteUserId = $Request.Body.SiteUserId -as [int]
    $Action = [string]$Request.Body.Action
    $Days = if ($Request.Body.Days) { $Request.Body.Days -as [int] } else { 90 }
    $DisplayName = $Request.Body.DisplayName ?? "user $SiteUserId"

    # Validate input before doing any work; bad input is a 400, not a failed upstream call.
    $ValidationError = if (-not $TenantFilter) {
        'tenantFilter is required.'
    } elseif (-not $SiteUrl -or -not $SiteUserId) {
        'SiteUrl and SiteUserId are required.'
    } elseif ($Action -notin @('Extend', 'Expire')) {
        "Action must be 'Extend' or 'Expire'."
    } elseif ($Action -eq 'Extend' -and ($null -eq $Days -or $Days -lt 1 -or $Days -gt 90)) {
        'Days must be between 1 and 90.'
    }
    if ($ValidationError) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ 'Results' = $ValidationError }
            })
    }

    try {
        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $Scope = "$($SharePointInfo.SharePointUrl)/.default"
        $VerboseHeaders = @{ Accept = 'application/json;odata=verbose' }

        # Resolve the user first: confirms they exist on this site and are a guest.
        $SpUser = New-GraphGetRequest -uri "$SiteUrl/_api/web/SiteUsers/GetById(@a)?@a=$SiteUserId&`$select=Id,Title,Email,LoginName,Expiration" -tenantid $TenantFilter -scope $Scope -extraHeaders @{ Accept = 'application/json;odata=nometadata' } -UseCertificate -AsApp $true
        if (-not $SpUser) {
            throw [System.Management.Automation.ItemNotFoundException]::new("User $SiteUserId was not found on $SiteUrl.")
        }
        if ($SpUser.LoginName -notmatch '(?i)#ext#|urn%3aspo%3aguest') {
            throw [System.ArgumentException]::new("$($SpUser.Title) is not a guest on $SiteUrl.")
        }
        $Who = "$($SpUser.Title) ($($SpUser.Email))"

        switch ($Action) {
            'Extend' {
                $NewExpiry = (Get-Date).ToUniversalTime().AddDays($Days).ToString('yyyy-MM-ddTHH:mm:ssZ')
                $Body = @{
                    __metadata = @{ type = 'SP.User' }
                    Expiration = $NewExpiry
                } | ConvertTo-Json -Compress

                $null = New-GraphPOSTRequest -uri "$SiteUrl/_api/web/SiteUsers/GetById(@a)?@a=$SiteUserId" -tenantid $TenantFilter -scope $Scope -AsApp $true -UseCertificate -type 'POST' -body $Body -contentType 'application/json;odata=verbose' -AddedHeaders ($VerboseHeaders + @{ 'X-HTTP-Method' = 'PATCH' })

                $Previous = if ($SpUser.Expiration) { $SpUser.Expiration } else { 'none' }
                $Results = "Extended $Who on $SiteUrl until $NewExpiry (was: $Previous)."
            }
            'Expire' {
                $null = New-GraphPOSTRequest -uri "$SiteUrl/_api/web/SiteUsers/GetById(@a)/Expire?@a=$SiteUserId" -tenantid $TenantFilter -scope $Scope -AsApp $true -UseCertificate -type 'POST' -body '' -contentType 'application/json;odata=verbose' -AddedHeaders $VerboseHeaders

                $Results = "Expired access for $Who on $SiteUrl. Entra account and other sites unchanged."
            }
        }

        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to $($Action.ToLower()) guest access for $DisplayName on $($SiteUrl): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })
}