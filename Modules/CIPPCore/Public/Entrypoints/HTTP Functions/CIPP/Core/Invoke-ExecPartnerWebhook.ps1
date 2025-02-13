function Invoke-ExecPartnerWebhook {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    Param($Request, $TriggerMetadata)

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
                if ($WebhookConfig.StandardsExcludeAllTenants -eq $true) {
                    $Results | Add-Member -MemberType NoteProperty -Name 'standardsExcludeAllTenants' -Value $true -Force
                }
            } catch {}
            if (!$Results) {
                $Results = [PSCustomObject]@{
                    webhoookUrl           = 'None'
                    lastModifiedTimestamp = 'Never'
                    webhookEvents         = @()
                }
            }
        }
        'CreateSubscription' {
            if ($Request.Body.EventType.value) {
                $Request.Body.EventType = $Request.Body.EventType.value
            }

            $BaseURL = ([System.Uri]$Request.Headers.'x-ms-original-url').Host
            $Webhook = @{
                TenantFilter  = $env:TenantID
                PartnerCenter = $true
                BaseURL       = $BaseURL
                EventType     = $Request.Body.EventType
                Headers = $Request.Headers.'x-ms-client-principal'
            }

            $Results = New-CIPPGraphSubscription @Webhook

            $ConfigTable = Get-CIPPTable -TableName Config
            $PartnerWebhookOnboarding = [PSCustomObject]@{
                PartitionKey               = 'Config'
                RowKey                     = 'PartnerWebhookOnboarding'
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

    Push-OutputBinding -Name Response -Value @{
        StatusCode = [System.Net.HttpStatusCode]::OK
        Body       = $Body
    }
}
