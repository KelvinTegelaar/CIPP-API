function Invoke-ExecPartnerWebhook {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    param($Request, $TriggerMetadata)
    switch ($Request.Query.Action) {
        'ListEventTypes' {
            $Uri = 'https://api.partnercenter.microsoft.com/webhooks/v1/registration/events'
            $Results = New-GraphGetRequest -uri $Uri -tenantid $env:TenantID -NoAuthCheck $true -scope 'https://api.partnercenter.microsoft.com/.default'
        }
        'ListSubscription' {
            try {
                $Uri = 'https://api.partnercenter.microsoft.com/webhooks/v1/registration'
                $Results = New-GraphGetRequest -uri $Uri -tenantid $env:TenantID -NoAuthCheck $true -scope 'https://api.partnercenter.microsoft.com/.default'

                $ConfigTable = Get-CIPPTable -TableName Config
                $WebhookConfig = Get-CIPPAzDataTableEntity @ConfigTable -Filter "RowKey eq 'PartnerWebhookOnboarding'"
                if ($WebhookConfig) {
                    $Results | Add-Member -MemberType NoteProperty -Name 'enabled' -Value ([bool]$WebhookConfig.Enabled) -Force
                    if ($WebhookConfig.StandardsExcludeAllTenants -eq $true) {
                        $Results | Add-Member -MemberType NoteProperty -Name 'standardsExcludeAllTenants' -Value $true -Force
                    }
                } else {
                    $Results | Add-Member -MemberType NoteProperty -Name 'enabled' -Value $false -Force
                }
            } catch {}
            if (!$Results) {
                $Results = [PSCustomObject]@{
                    webhookUrl            = 'None'
                    lastModifiedTimestamp = 'Never'
                    webhookEvents         = @()
                    enabled               = $false
                }
            }

            # The URL that would be registered if the subscription were saved right now, so the UI can
            # flag a subscription still pointing at a previous CIPP URL.
            $CurrentHostname = Get-CIPPHostname -Headers $Request.Headers
            if ($CurrentHostname) {
                $Results | Add-Member -MemberType NoteProperty -Name 'expectedWebhookUrl' -Value "https://$CurrentHostname/API/PublicWebhooks?CIPPID=$($env:TenantID)&Type=PartnerCenter" -Force
            }
        }
        'CreateSubscription' {
            if ($Request.Body.EventType.value) {
                $Request.Body.EventType = $Request.Body.EventType.value
            }

            # Resolve the URL CIPP is served from at the time of submit, and store it for background jobs
            $BaseURL = Get-CIPPHostname -Headers $Request.Headers -Save
            $Webhook = @{
                TenantFilter  = $env:TenantID
                PartnerCenter = $true
                BaseURL       = $BaseURL
                EventType     = $Request.Body.EventType
                Headers       = $Request.Headers.'x-ms-client-principal'
            }

            $Results = New-CIPPGraphSubscription @Webhook

            $ConfigTable = Get-CIPPTable -TableName Config
            $PartnerWebhookOnboarding = [PSCustomObject]@{
                PartitionKey               = 'Config'
                RowKey                     = 'PartnerWebhookOnboarding'
                Enabled                    = [bool]$Request.Body.enabled
                StandardsExcludeAllTenants = $Request.Body.standardsExcludeAllTenants
            }
            Add-CIPPAzDataTableEntity @ConfigTable -Entity $PartnerWebhookOnboarding -Force | Out-Null
        }
        'SendTest' {
            $Results = New-GraphPOSTRequest -uri 'https://api.partnercenter.microsoft.com/webhooks/v1/registration/validationEvents' -tenantid $env:TenantID -NoAuthCheck $true -scope 'https://api.partnercenter.microsoft.com/.default'
        }
        'ValidateTest' {
            $Results = New-GraphGetRequest -uri "https://api.partnercenter.microsoft.com/webhooks/v1/registration/validationEvents/$($Request.Query.CorrelationId)" -tenantid $env:TenantID -NoAuthCheck $true -scope 'https://api.partnercenter.microsoft.com/.default'
        }
        default {
            $Results = 'Invalid Action'
        }
    }

    $Body = [PSCustomObject]@{
        Results  = $Results
        Metadata = [PSCustomObject]@{
            Action = $Request.Query.Action
        }
    }

    return [HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::OK
        Body       = $Body
    }
}
