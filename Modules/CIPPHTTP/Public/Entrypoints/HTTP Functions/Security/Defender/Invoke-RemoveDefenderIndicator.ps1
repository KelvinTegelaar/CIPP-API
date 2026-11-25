function Invoke-RemoveDefenderIndicator {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.Defender.ReadWrite
    .SYNOPSIS
        Remove Defender custom indicators from one tenant
    .DESCRIPTION
        Removes up to 500 Microsoft Defender for Endpoint custom indicators from one tenant by their Defender ids, as listed by ListDefenderIndicators. Ids that no longer exist are treated as removed, so a retry is safe. Defender can take a minute to show the change in its list.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    # One tenant: its default domain or tenant id.
    $TenantFilter = $Request.Body.tenantFilter
    # The Defender ids of the indicators to remove, up to 500.
    $IndicatorIds = $Request.Body.IndicatorIds

    if ($TenantFilter -isnot [string] -or [string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -eq 'AllTenants' -or $TenantFilter -like 'group:*') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'tenantFilter must name one tenant.' } })
    }
    $Ids = [System.Collections.Generic.List[string]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($Id in @($IndicatorIds)) {
        if (($Id -isnot [string] -and $Id -isnot [int] -and $Id -isnot [long]) -or "$Id" -notmatch '\A[0-9A-Za-z-]{1,64}\z') {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'IndicatorIds must be a list of Defender indicator ids.' } })
        }
        if ($Seen.Add("$Id")) { $Ids.Add("$Id") }
    }
    if ($Ids.Count -eq 0 -or $Ids.Count -gt 500) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'IndicatorIds must hold between 1 and 500 ids.' } })
    }

    try {
        $Body = @{ IndicatorIds = @($Ids) } | ConvertTo-Json -Compress
        $null = New-GraphPOSTRequest -uri 'https://api.securitycenter.microsoft.com/api/indicators/BatchDelete' -tenantid $TenantFilter -body $Body -scope 'https://api.securitycenter.microsoft.com/.default' -AsApp $true
        $Result = "Removed $($Ids.Count) Defender $(if ($Ids.Count -eq 1) { 'indicator' } else { 'indicators' }) from $TenantFilter, or they were already gone. Defender can take a minute to show the change."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Removed Defender indicators (ids $($Ids -join ', '))" -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to remove $($Ids.Count) Defender $(if ($Ids.Count -eq 1) { 'indicator' } else { 'indicators' }) from $($TenantFilter): $($ErrorMessage.NormalizedError) Refresh the list to see which remain, then try again."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to remove Defender indicators (ids $($Ids -join ', ')): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
