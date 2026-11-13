function Invoke-ExecPartnerWebhook {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    param($Request, $TriggerMetadata)

    # Multi-partner: manage the webhook of a specific partner tenant (defaults to the primary)
    $PartnerTenantId = $Request.Query.partnerTenantId ?? $Request.Body.partnerTenantId.value ?? $Request.Body.partnerTenantId
    if (!$PartnerTenantId -or -not (Get-CIPPPartnerTenantList | Where-Object { $_.partnerTenantId -eq $PartnerTenantId })) {
        $PartnerTenantId = $env:TenantID
    }
    $ConfigRowKey = if ($PartnerTenantId -eq $env:TenantID) { 'PartnerWebhookOnboarding' } else { "PartnerWebhookOnboarding-$PartnerTenantId" }

    switch ($Request.Query.Action) {
        'ListEventTypes' {
            $Uri = 'https://api.partnercenter.microsoft.com/webhooks/v1/registration/events'
            $Results = New-GraphGetRequest -uri $Uri -tenantid $PartnerTenantId -NoAuthCheck $true -scope 'https://api.partnercenter.microsoft.com/.default'
        }
        'ListSubscription' {
            try {
                $Uri = 'https://api.partnercenter.microsoft.com/webhooks/v1/registration'
                $Results = New-GraphGetRequest -uri $Uri -tenantid $PartnerTenantId -NoAuthCheck $true -scope 'https://api.partnercenter.microsoft.com/.default'

                $ConfigTable = Get-CIPPTable -TableName Config
                $WebhookConfig = Get-CIPPAzDataTableEntity @ConfigTable -Filter "RowKey eq '$ConfigRowKey'"
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
            # flag a subscription still pointing at a previous CIPP URL. Resolved from the custom
            # domain bound to the instance rather than the host the admin browsed in on - otherwise
            # visiting the *.azurewebsites.net URL tells you to re-register against it, which is the
            # opposite of what warmup reconciles the stored URL to.
            $CurrentHostname = Get-CIPPHostname -Headers $Request.Headers -PreferCustomDomain
            if ($CurrentHostname) {
                $Results | Add-Member -MemberType NoteProperty -Name 'expectedWebhookUrl' -Value "https://$CurrentHostname/api/PublicWebhooks?CIPPID=$($PartnerTenantId)&Type=PartnerCenter" -Force
                $Results | Add-Member -MemberType NoteProperty -Name 'instanceHostname' -Value $CurrentHostname -Force
            }

            # Surfaced so the UI can explain which domain was picked when several are bound.
            try {
                $SiteState = Get-CIPPSiteHostname -IncludeStatus -NoFallback
                $Results | Add-Member -MemberType NoteProperty -Name 'customDomains' -Value @($SiteState.CustomHostnames) -Force
            } catch {
                Write-Information "ExecPartnerWebhook: custom domain lookup failed: $($_.Exception.Message)"
            }
        }
        'CreateSubscription' {
            if ($Request.Body.EventType.value) {
                $Request.Body.EventType = $Request.Body.EventType.value
            }

            # Resolve the URL CIPP is published on and store it for background jobs. The bound custom
            # domain wins over the request host so a save made from the *.azurewebsites.net URL does
            # not register Partner Center against a hostname warmup will reconcile away again.
            $BaseURL = Get-CIPPHostname -Headers $Request.Headers -PreferCustomDomain -Save
            $Webhook = @{
                TenantFilter    = $PartnerTenantId
                PartnerCenter   = $true
                PartnerTenantId = $PartnerTenantId
                BaseURL         = $BaseURL
                EventType       = $Request.Body.EventType
                Headers         = $Request.Headers.'x-ms-client-principal'
            }

            $Results = New-CIPPGraphSubscription @Webhook

            $ConfigTable = Get-CIPPTable -TableName Config
            $PartnerWebhookOnboarding = [PSCustomObject]@{
                PartitionKey               = 'Config'
                RowKey                     = $ConfigRowKey
                Enabled                    = [bool]$Request.Body.enabled
                StandardsExcludeAllTenants = $Request.Body.standardsExcludeAllTenants
            }
            Add-CIPPAzDataTableEntity @ConfigTable -Entity $PartnerWebhookOnboarding -Force | Out-Null
            # Subscription create/update is logged by New-CIPPGraphSubscription; log the onboarding config write here.
            Write-LogMessage -headers $Request.Headers -API ($Request.Params.CIPPEndpoint) -tenant 'Global' -message "Partner webhook onboarding config saved (Enabled=$([bool]$Request.Body.enabled))" -Sev 'Info'
        }
        'SendTest' {
            $Results = New-GraphPOSTRequest -uri 'https://api.partnercenter.microsoft.com/webhooks/v1/registration/validationEvents' -tenantid $PartnerTenantId -NoAuthCheck $true -scope 'https://api.partnercenter.microsoft.com/.default'
        }
        'ValidateTest' {
            $Results = New-GraphGetRequest -uri "https://api.partnercenter.microsoft.com/webhooks/v1/registration/validationEvents/$($Request.Query.CorrelationId)" -tenantid $PartnerTenantId -NoAuthCheck $true -scope 'https://api.partnercenter.microsoft.com/.default'
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

