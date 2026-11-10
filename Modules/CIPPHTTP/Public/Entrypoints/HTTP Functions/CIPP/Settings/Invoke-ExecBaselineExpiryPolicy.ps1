function Invoke-ExecBaselineExpiryPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    .SYNOPSIS
        Set the baseline expiry policy
    .DESCRIPTION
        Sets the instance-wide default and maximum expiry, in days, for accepted baseline
        deviations and tenant overrides. 0 means no default or no maximum.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Days from now that a new acceptance or override expires by default. 0 for no default.
    $DefaultDays = if ("$($Request.Body.defaultDays)" -match '^\d+$') { [int]$Request.Body.defaultDays }
    # Furthest away, in days, that an expiry may be. 0 for no maximum.
    $MaxDays = if ("$($Request.Body.maxDays)" -match '^\d+$') { [int]$Request.Body.maxDays }
    $ValidationError = if ($null -eq $DefaultDays -or $null -eq $MaxDays) {
        'defaultDays and maxDays are required whole numbers of 0 or more.'
    } elseif ($DefaultDays -gt 3650 -or $MaxDays -gt 3650) {
        'Days must be between 0 and 3650.'
    } elseif ($MaxDays -gt 0 -and $DefaultDays -gt $MaxDays) {
        'The default cannot be longer than the maximum.'
    }
    if ($ValidationError) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = $ValidationError } })
    }

    try {
        $Table = Get-CIPPTable -TableName Config
        Add-CIPPAzDataTableEntity @Table -Force -Entity @{
            PartitionKey = 'BaselineExpiry'
            RowKey       = 'Settings'
            defaultDays  = $DefaultDays
            maxDays      = $MaxDays
        }
        $Result = 'Saved the baseline expiry policy: default {0}, maximum {1}.' -f $(if ($DefaultDays) { "$DefaultDays days" } else { 'none' }), $(if ($MaxDays) { "$MaxDays days" } else { 'none' })
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "Failed to save the baseline expiry policy: $($_.Exception.Message)"
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message $Result -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
