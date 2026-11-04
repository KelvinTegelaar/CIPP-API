function Invoke-ListDeletedApplications {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.Read
    .DESCRIPTION
        Lists the app registrations and enterprise apps (service principals) deleted in the last 30 days, which Entra
        can still restore. Each row has the days left before Entra removes it for good, and whether the matching app
        registration or enterprise app is deleted too: restoring one does not restore the other.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Select a single tenant' } })
    }

    try {
        $Applications = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/directory/deletedItems/microsoft.graph.application?$select=id,appId,displayName,createdDateTime,deletedDateTime,signInAudience,publisherDomain&$top=999' -tenantid $TenantFilter | Where-Object { $_.id })
        $ServicePrincipals = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/directory/deletedItems/microsoft.graph.servicePrincipal?$select=id,appId,displayName,createdDateTime,deletedDateTime,appOwnerOrganizationId,publisherName,servicePrincipalType&$top=999' -tenantid $TenantFilter | Where-Object { $_.id })

        $AppByAppId = @{}
        foreach ($App in $Applications) { if ($App.appId) { $AppByAppId[([string]$App.appId).ToLowerInvariant()] = $App } }
        $SpByAppId = @{}
        foreach ($Sp in $ServicePrincipals) { if ($Sp.appId) { $SpByAppId[([string]$Sp.appId).ToLowerInvariant()] = $Sp } }

        $Now = [datetimeoffset]::UtcNow
        $NewRow = {
            param($Object, $Type, $Publisher, $Related)
            $DaysLeft = if ($Object.deletedDateTime) { [int][math]::Max(0, 30 - [math]::Floor(($Now - [datetimeoffset]$Object.deletedDateTime).TotalDays)) }
            [PSCustomObject]@{
                id               = [string]$Object.id
                appId            = [string]$Object.appId
                displayName      = [string]$Object.displayName
                type             = $Type
                publisher        = $Publisher
                createdDateTime  = $Object.createdDateTime
                deletedDateTime  = $Object.deletedDateTime
                daysLeft         = $DaysLeft
                relatedDeleted   = [bool]$Related
                relatedDeletedId = if ($Related) { [string]$Related.id } else { $null }
            }
        }

        $Rows = @(
            foreach ($App in $Applications) {
                & $NewRow $App 'App registration' ([string]$App.publisherDomain) $SpByAppId[([string]$App.appId).ToLowerInvariant()]
            }
            foreach ($Sp in $ServicePrincipals) {
                & $NewRow $Sp 'Enterprise app' ([string]$Sp.publisherName) $AppByAppId[([string]$Sp.appId).ToLowerInvariant()]
            }
        ) | Sort-Object -Property @{ Expression = { if ($_.deletedDateTime) { [datetimeoffset]$_.deletedDateTime } else { [datetimeoffset]::MinValue } }; Descending = $true }

        $Body = @{ Results = @($Rows) }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to list deleted applications: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Results = "Failed to list deleted applications: $($ErrorMessage.NormalizedError)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
