function Get-CIPPAlertCheckExtension {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        $TenantFilter,
        [Alias('input')]
        $InputValue
    )

    try {
        $CheckTable = Get-CippTable -tablename 'CheckExtensionAlerts'
        $LastRunTable = Get-CippTable -tablename 'AlertLastRun'
        $LastRunKey = "$TenantFilter-Get-CIPPAlertCheckExtension"

        # Get the last run timestamp for this tenant to only fetch new alerts
        $LastRun = Get-CIPPAzDataTableEntity @LastRunTable -Filter "PartitionKey eq 'AlertLastRun' and RowKey eq '$LastRunKey'" | Select-Object -First 1
        $Since = if ($LastRun.Timestamp) {
            $LastRun.Timestamp.UtcDateTime
        } else {
            (Get-Date).AddDays(-1).ToUniversalTime()
        }
        $SinceString = $Since.ToString('yyyy-MM-ddTHH:mm:ssZ')

        $CheckAlerts = Get-CIPPAzDataTableEntity @CheckTable -Filter "PartitionKey eq 'CheckAlert' and tenantFilter eq '$TenantFilter' and Timestamp ge datetime'$SinceString'"

        $AlertData = foreach ($Alert in $CheckAlerts) {
            [PSCustomObject]@{
                Message                  = "Phishing alert: $($Alert.type) detected for user $($Alert.potentialUserName) at URL $($Alert.url) - $($Alert.reason)"
                Type                     = $Alert.type
                URL                      = $Alert.url
                Reason                   = $Alert.reason
                Score                    = $Alert.score
                Threshold                = $Alert.threshold
                PotentialUserName        = $Alert.potentialUserName
                PotentialUserDisplayName = $Alert.potentialUserDisplayName
                ReportedByIP             = $Alert.reportedByIP
                Tenant                   = $TenantFilter
            }
        }

        if ($AlertData) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-AlertMessage -message "Check Extension alert failed: $($ErrorMessage.NormalizedError)" -tenant $TenantFilter -LogData $ErrorMessage
    }
}
