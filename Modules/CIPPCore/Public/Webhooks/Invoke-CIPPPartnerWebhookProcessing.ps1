function Invoke-CippPartnerWebhookProcessing {
    [CmdletBinding()]
    param (
        $Data
    )

    try {
        if ($Data.AuditUri) {
            $AuditLog = New-GraphGetRequest -uri $Data.AuditUri -tenantid $env:TenantID -NoAuthCheck $true -scope 'https://api.partnercenter.microsoft.com/.default'
        }

        switch ($Data.EventName) {
            'test-created' {
                Write-LogMessage -API 'Webhooks' -message 'Partner Center webhook test received' -Sev 'Info'
            }
            default {
                if ($Data.EventName -eq 'granular-admin-relationship-approved') {
                    if ($AuditLog.resourceNewValue) {
                        $AuditObj = $AuditLog.resourceNewValue | ConvertFrom-Json
                        Write-LogMessage -API 'Webhooks' -message "Partner Webhook: GDAP Relationship for $($AuditObj.customer.organizationDisplayName) was approved, starting onboarding" -LogData $AuditObj -Sev 'Alert'
                        $Id = $AuditObj.Id
                        $OnboardingSteps = [PSCustomObject]@{
                            'Step1' = @{
                                'Status'  = 'pending'
                                'Title'   = 'Step 1: GDAP Invite'
                                'Message' = 'Waiting for onboarding job to start'
                            }
                            'Step2' = @{
                                'Status'  = 'pending'
                                'Title'   = 'Step 2: GDAP Role Test'
                                'Message' = 'Waiting for Step 1'
                            }
                            'Step3' = @{
                                'Status'  = 'pending'
                                'Title'   = 'Step 3: GDAP Group Mapping'
                                'Message' = 'Waiting for Step 2'
                            }
                            'Step4' = @{
                                'Status'  = 'pending'
                                'Title'   = 'Step 4: CPV Refresh'
                                'Message' = 'Waiting for Step 3'
                            }
                            'Step5' = @{
                                'Status'  = 'pending'
                                'Title'   = 'Step 5: Graph API Test'
                                'Message' = 'Waiting for Step 4'
                            }
                        }
                        $TenantOnboarding = [PSCustomObject]@{
                            PartitionKey    = 'Onboarding'
                            RowKey          = [string]$Id
                            CustomerId      = ''
                            Status          = 'queued'
                            OnboardingSteps = [string](ConvertTo-Json -InputObject $OnboardingSteps -Compress)
                            Relationship    = ''
                            Logs            = ''
                            Exception       = ''
                        }

                        $OnboardItem = @{ Id = $Id }

                        # Check for partner webhook onboarding settings
                        $ConfigTable = Get-CIPPTable -TableName Config
                        $WebhookConfig = Get-CIPPAzDataTableEntity @ConfigTable -Filter "RowKey eq 'PartnerWebhookOnboarding'"

                        # Only proceed if automated onboarding is enabled
                        if ($WebhookConfig.Enabled -eq $true) {
                            if ($WebhookConfig.StandardsExcludeAllTenants -eq $true) {
                                $OnboardItem.StandardsExcludeAllTenants = $true
                            }

                            # Add onboarding entry to the table
                            $OnboardTable = Get-CIPPTable -TableName 'TenantOnboarding'
                            Add-CIPPAzDataTableEntity @OnboardTable -Entity $TenantOnboarding -Force -ErrorAction Stop

                            # Start onboarding
                            Push-ExecOnboardTenantQueue -Item $OnboardItem
                            Write-LogMessage -API 'Webhooks' -message "Automated onboarding started for relationship $Id" -Sev 'Info'
                        } else {
                            Write-LogMessage -API 'Webhooks' -message "Automated onboarding is disabled. GDAP relationship $Id approved but not onboarded automatically." -Sev 'Info'
                        }
                    } else {
                        if ($AuditLog) {
                            Write-LogMessage -API 'Webhooks' -message "Partner Center $($Data.EventName) audit log webhook received" -LogData $AuditObj -Sev 'Alert'
                        } else {
                            Write-LogMessage -API 'Webhooks' -message "Partner Center $($Data.EventName) webhook received" -LogData $Data -Sev 'Alert'
                        }
                    }
                }
            }
        }
    } catch {
        Write-LogMessage -API 'Webhooks' -message 'Error processing Partner Center webhook' -LogData (Get-CippException -Exception $_) -Sev 'Error'
    }
}
