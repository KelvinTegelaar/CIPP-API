function Invoke-ExecPartnerWebhook {
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
            $BaseURL = ([System.Uri]$request.headers.'x-ms-original-url').Host
            $Webhook = @{
                TenantFilter  = $env:TenantId
                PartnerCenter = $true
                BaseURL       = $BaseURL
                EventType     = $Request.body.EventType
                ExecutingUser = $Request.headers.'x-ms-client-principal'
            }
            $Results = New-CIPPGraphSubscription @Webhook
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