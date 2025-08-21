function Get-CIPPAlertSmtpAuthSuccess {
    <#
    .FUNCTIONALITY
        Entrypoint – Check sign-in logs for SMTP AUTH with success status
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        # Graph API endpoint for sign-ins
        $uri = "https://graph.microsoft.com/v1.0/auditLogs/signIns?`$filter=clientAppUsed eq 'SMTP' and status/errorCode eq 0"

        # Call Graph API for the given tenant
        $SignIns = New-GraphGetRequest -uri $uri -tenantid $TenantFilter

        # Select only the properties you care about
        $AlertData = $SignIns.value | Select-Object userPrincipalName, createdDateTime, clientAppUsed, ipAddress, status

        # Write results into the alert pipeline
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

    } catch {
        # Suppress errors if no data returned
        # Uncomment if you want explicit error logging
        # Write-AlertMessage -tenant $($TenantFilter) -message "Failed to query SMTP AUTH sign-ins for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
