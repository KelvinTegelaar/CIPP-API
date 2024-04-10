function Invoke-CippPartnerWebhookProcessing {
    [CmdletBinding()]
    param (
        $Data
    )

    Switch ($Data.EventType) {
        'test-created' {
            Write-LogMessage -API 'Webhooks' -message 'Partner Center webhook test received' -Sev 'Info'
        }
        default {
            Write-LogMessage -API 'Webhooks' -message "Partner Center webhook received: $($Data | ConvertTo-Json -Depth 5)" -Sev 'Info'
        }
    }
}
