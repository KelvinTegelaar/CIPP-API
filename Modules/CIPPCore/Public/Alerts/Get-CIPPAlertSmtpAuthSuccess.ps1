function Get-CIPPAlertSmtpAuthSuccess {
    <#
    .FUNCTIONALITY
        Entrypoint – Check sign-in logs for SMTP AUTH with success status
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        $lookupDays = if ($InputValue.SmtpAuthSuccessDays) { [int]$InputValue.SmtpAuthSuccessDays } else { 7 }
        $lookupDays = [Math]::Min($lookupDays, 30)

        $endDateTime = (Get-Date).ToUniversalTime()
        $startDateTime = $endDateTime.AddDays(-$lookupDays)
        $startDateTimeString = $startDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $endDateTimeString = $endDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')

        # Graph API endpoint for sign-ins
        $uri = "https://graph.microsoft.com/v1.0/auditLogs/signIns?`$filter=createdDateTime ge $startDateTimeString and createdDateTime le $endDateTimeString and (clientAppUsed eq 'Authenticated SMTP' or clientAppUsed eq 'SMTP') and status/errorCode eq 0"

        # Call Graph API for the given tenant
        $SignIns = New-GraphGetRequest -uri $uri -tenantid $TenantFilter

        # Select only the properties you care about
        $AlertData = $SignIns | Select-Object userPrincipalName, createdDateTime, clientAppUsed, ipAddress, status, @{Name = 'Tenant'; Expression = { $TenantFilter } }

        # Write results into the alert pipeline
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

    } catch {
        # Suppress errors if no data returned
        # Uncomment if you want explicit error logging
        # Write-AlertMessage -tenant $($TenantFilter) -message "Failed to query SMTP AUTH sign-ins for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
