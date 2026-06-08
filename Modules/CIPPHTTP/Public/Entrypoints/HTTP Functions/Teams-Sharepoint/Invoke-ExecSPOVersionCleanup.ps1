function Invoke-ExecSPOVersionCleanup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $SiteUrl = $Request.Body.SiteUrl
    $BatchDeleteMode = [int]($Request.Body.BatchDeleteMode ?? 2)
    $DeleteOlderThanDays = [int]($Request.Body.DeleteOlderThanDays ?? -1)
    $MajorVersionLimit = [int]($Request.Body.MajorVersionLimit ?? -1)
    $MajorWithMinorVersionsLimit = [int]($Request.Body.MajorWithMinorVersionsLimit ?? -1)

    try {
        $Params = @{
            TenantFilter                = $TenantFilter
            SiteUrl                     = $SiteUrl
            BatchDeleteMode             = $BatchDeleteMode
            DeleteOlderThanDays         = $DeleteOlderThanDays
            MajorVersionLimit           = $MajorVersionLimit
            MajorWithMinorVersionsLimit = $MajorWithMinorVersionsLimit
        }
        $null = Start-CIPPSiteVersionCleanup @Params
        $Result = "Successfully started version cleanup job for $SiteUrl"
        Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message $Result -sev Info
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Failed to start version cleanup for $SiteUrl : $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $Result = "Failed to start version cleanup: $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode ?? [HttpStatusCode]::OK
        Body       = @{ Results = $Result }
    }
}
