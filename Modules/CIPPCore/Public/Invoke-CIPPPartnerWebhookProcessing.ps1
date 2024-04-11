function Invoke-CippPartnerWebhookProcessing {
    [CmdletBinding()]
    param (
        $Data
    )

    Switch ($Data.EventName) {
        'test-created' {
            Write-LogMessage -API 'Webhooks' -message 'Partner Center webhook test received' -Sev 'Info'
        }
        default {
            if ($Data.AuditUri) {
                $AuditLog = New-GraphGetRequest -uri $Data.AuditUri -tenantid $env:TenantID -NoAuthCheck $true -scope 'https://api.partnercenter.microsoft.com/.default'
                Write-Logessage -API 'Webhooks' -message "Partner Center $($Data.EventName) audit log received" -LogData $AuditLog -Sev 'Info'
            } else {
                Write-LogMessage -API 'Webhooks' -message 'Partner Center webhook received (no audit)' -LogData $Data -Sev 'Info'
            }
        }
    }
}
