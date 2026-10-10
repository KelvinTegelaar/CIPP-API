function Invoke-ExecAddTrustedIP {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    .SYNOPSIS
        Adds IP addresses or ranges to CIPP's IP allow/block list.
    .DESCRIPTION
        Sets each IP address or CIDR range (IPv4 or IPv6) to Trusted, Blocked or NotTrusted (neutral) for one tenant, or for every tenant with tenantfilter=AllTenants. A tenant entry overrides an AllTenants entry for the same range, and the most specific range decides an address. The audit-log alerts treat Trusted addresses as known; the BEC investigation uses Trusted and Blocked entries as confirmed-safe and confirmed-compromised IPs.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $tenantfilter = $Request.Query.tenantfilter
    if (-not $tenantfilter) {
        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ results = "Missing required query parameter 'tenantfilter'" }
        })
    }

    $tenantDomain = if ($tenantfilter -eq 'AllTenants') { 'AllTenants' }
    else { (Get-Tenants -TenantFilter $tenantfilter).defaultDomainName }
    if (-not $tenantDomain) {
        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ results = "Invalid tenantfilter '$tenantfilter'" }
        })
    }

    # Trusted, Blocked, or NotTrusted to make the entry neutral again
    $State = [string]$Request.Body.State
    if ($State -notin @('Trusted', 'Blocked', 'NotTrusted')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ results = "State must be Trusted, Blocked or NotTrusted" }
            })
    }
    # IP addresses or CIDR ranges (IPv4 or IPv6); one entry may also hold several separated by commas or spaces
    $RawIPs = foreach ($Value in $Request.Body.IP) { [string]$Value -split '[,;\s]+' }
    $Ranges = try {
        @($RawIPs | Where-Object { $_ } | ForEach-Object { ConvertTo-CIPPIPRange -Value $_ } | Select-Object -Unique)
    } catch {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ results = $_.Exception.Message }
            })
    }
    if ($Ranges.Count -eq 0) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ results = 'At least one IP address or range is required' }
            })
    }
    # Optional note shown with the entry
    $Note = [string]$Request.Body.Note

    try {
        $Table = Get-CippTable -tablename 'trustedIps'
        foreach ($Range in $Ranges) {
            # '/' is not allowed in a table key: the key carries '_' and the range itself is stored alongside
            Add-CIPPAzDataTableEntity @Table -Entity @{
                PartitionKey = $tenantDomain
                RowKey       = $Range -replace '/', '_'
                Range        = $Range
                state        = $State
                Note         = $Note
            } -Force
        }
        $Result = "Set $($Ranges -join ', ') to $State for $($tenantDomain)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $tenantDomain -message $Result -Sev 'Info'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ results = $Result }
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to add trusted IP(s) for $($tenantDomain): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $tenantDomain -message $Result -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ results = $Result }
            })
    }
}
