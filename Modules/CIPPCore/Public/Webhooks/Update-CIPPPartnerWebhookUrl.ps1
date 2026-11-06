function Update-CIPPPartnerWebhookUrl {
    <#
    .SYNOPSIS
        Re-registers Partner Center webhook subscriptions when they point at a stale CIPP URL.
    .DESCRIPTION
        The subscription held in Partner Center records the exact address CIPP was reachable at when
        it was created, and it does not follow a change of hostname. Partner Center carries on
        delivering events to the old address, so tenants silently stop being onboarded and partner
        alerts stop arriving with nothing failing outright.

        Runs at warmup, straight after Update-CIPPInstanceHostname has settled what this instance is
        published on. Reconciles each configured partner tenant's subscription independently.

        Deliberately conservative, because this writes to an external service. Per partner it does
        nothing unless automated onboarding is enabled for that partner, ARM authoritatively
        confirmed the bound hostname, and Partner Center is actually holding a different URL.
        Registered event types are carried across so a repair never narrows the subscription.

        Never throws; warmup steps are soft-fail by design.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Update-CIPPPartnerWebhookUrl
    #>
    [CmdletBinding()]
    param()

    $States = [System.Collections.Generic.List[object]]::new()

    try {
        if ([string]::IsNullOrWhiteSpace($env:TenantID)) {
            Write-Information '[Partner-Webhook] No partner tenant is configured yet - nothing to reconcile'
            return $States
        }

        $ConfigTable = Get-CIPPTable -TableName 'Config'
        $SiteState = $null

        foreach ($Partner in @(Get-CIPPPartnerTenant)) {
            $PartnerTenantId = "$($Partner.RowKey)"
            $ConfigRowKey = if ($Partner.IsPrimary) { 'PartnerWebhookOnboarding' } else { "PartnerWebhookOnboarding-$PartnerTenantId" }
            $State = [PSCustomObject]@{
                PartnerTenantId = $PartnerTenantId
                Enabled         = $false
                CurrentUrl      = $null
                ExpectedUrl     = $null
                Updated         = $false
                Reason          = $null
            }
            $States.Add($State)

            $WebhookConfig = Get-CIPPAzDataTableEntity @ConfigTable -Filter "RowKey eq '$ConfigRowKey'"
            if ($WebhookConfig.Enabled -ne $true) {
                $State.Reason = 'Automated onboarding is disabled - leaving the Partner Center subscription alone'
                Write-Information "[Partner-Webhook] [$PartnerTenantId] $($State.Reason)"
                continue
            }
            $State.Enabled = $true

            if (-not $SiteState) {
                $SiteState = Get-CIPPSiteHostname -IncludeStatus -NoFallback
                if (-not $SiteState.Discovered -or [string]::IsNullOrWhiteSpace($SiteState.PreferredHostname)) {
                    $State.Reason = "Bound hostnames could not be enumerated - not rewriting an external registration on a guess: $($SiteState.Error)"
                    Write-Information "[Partner-Webhook] $($State.Reason)"
                    return $States
                }
                if ($SiteState.CustomHostnames.Count -gt 1) {
                    Write-Information "[Partner-Webhook] $($SiteState.CustomHostnames.Count) custom domains bound ($($SiteState.CustomHostnames -join ', ')) - registering against the first, '$($SiteState.PreferredHostname)'"
                }
            }
            $Hostname = $SiteState.PreferredHostname
            $State.ExpectedUrl = "https://$Hostname/api/PublicWebhooks?CIPPID=$($PartnerTenantId)&Type=PartnerCenter"

            # Read before write: never "repair" a subscription whose current state we could not read
            try {
                $Existing = New-GraphGetRequest -uri 'https://api.partnercenter.microsoft.com/webhooks/v1/registration' -tenantid $PartnerTenantId -NoAuthCheck $true -scope 'https://api.partnercenter.microsoft.com/.default'
            } catch {
                $State.Reason = "Could not read the current Partner Center subscription - skipping: $($_.Exception.Message)"
                Write-Information "[Partner-Webhook] [$PartnerTenantId] $($State.Reason)"
                continue
            }
            $State.CurrentUrl = $Existing.webhookUrl

            if ($Existing.webhookUrl -eq $State.ExpectedUrl) {
                $State.Reason = "Partner Center already points at $($State.ExpectedUrl)"
                Write-Information "[Partner-Webhook] [$PartnerTenantId] $($State.Reason)"
                continue
            }

            Write-Information "[Partner-Webhook] [$PartnerTenantId] Subscription points at '$($Existing.webhookUrl)' but this instance is published on '$Hostname' - re-registering"

            # Carry the registered events across so re-registration keeps the admin's selection
            $EventTypes = @($Existing.webhookEvents)
            $Result = New-CIPPGraphSubscription -PartnerCenter -PartnerTenantId $PartnerTenantId -BaseURL $Hostname -EventType $EventTypes -APIName 'Partner Webhook Reconciliation'

            # New-CIPPGraphSubscription reports failures as a returned string rather than throwing
            $State.Reason = [string]$Result
            $State.Updated = $State.Reason -notmatch '^Failed'
            Write-Information "[Partner-Webhook] [$PartnerTenantId] $($State.Reason)"
        }
    } catch {
        Write-Information "[Partner-Webhook] Reconciliation failed (non-fatal): $($_.Exception.Message)"
    }

    return $States
}
