function Invoke-ExecRemoveEnrollmentRestriction {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.ReadWrite
    .DESCRIPTION
        Deletes an enrollment (device type) restriction: every Graph object behind it (ids), which for Android is both the work profile and the device administrator object. Only single-platform restrictions can be deleted; the tenant's default restriction is refused.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $DisplayName = $Request.Body.displayName
    $Ids = @(@($Request.Body.ids ?? $Request.Body.id) | ForEach-Object { "$_".Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    try {
        if ($Ids.Count -eq 0) { throw 'No restriction id was supplied.' }
        # Ids like '<account>_SinglePlatformRestriction'; the default ends in _DefaultPlatformRestrictions.
        $NotSingle = @($Ids | Where-Object { $_ -notmatch '_SinglePlatformRestriction$' })
        if ($NotSingle.Count -gt 0) { throw "Only restrictions for specific groups can be deleted, not $($NotSingle -join ', ')." }

        foreach ($Id in $Ids) {
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations/$Id" -tenantid $TenantFilter -type DELETE
        }
        $Result = "Deleted enrollment restriction $($DisplayName ?? ($Ids -join ', '))"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to delete enrollment restriction $($DisplayName ?? ($Ids -join ', ')): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
