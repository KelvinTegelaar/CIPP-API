function Update-CIPPPartnerWebhookUrl {
    <#
    .SYNOPSIS
        Re-registers the Partner Center webhook subscription when it points at a stale CIPP URL.
    .DESCRIPTION
        The subscription held in Partner Center records the exact address CIPP was reachable at when
        it was created, and it does not follow a change of hostname. Partner Center carries on
        delivering events to the old address, so tenants silently stop being onboarded and partner
        alerts stop arriving with nothing failing outright - the only fix was for an admin to notice
        the warning on the Automated Onboarding page and re-save it by hand.

        Runs at warmup, straight after Update-CIPPInstanceHostname has settled what this instance is
        published on, so a container that comes up on a new custom domain repairs its own
        subscription.

        Deliberately conservative, because unlike the rest of warmup this writes to an external
        service. It does nothing unless:
          - automated onboarding is enabled. A disabled subscription is not CIPP's to correct.
          - ARM authoritatively confirmed the bound hostname. The stored instance URL is NOT good
            enough here: on a fresh container it is the platform hostname, so repairing from it
            would point a working custom domain at *.azurewebsites.net rather than fix anything.
          - Partner Center is actually holding a different URL. A failed read is not a mismatch, so
            an unreachable Partner Center means no write at all.

        The currently registered event types are carried across, so a repair never silently narrows
        the subscription to the two events New-CIPPGraphSubscription requires.

        Warmup runs on every node, so several may repair the same stale subscription at once. The
        writes are identical and the losers of that race find the URL already correct.

        Never throws; warmup steps are soft-fail by design.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Update-CIPPPartnerWebhookUrl
    #>
    [CmdletBinding()]
    param()

    $State = [PSCustomObject]@{
        Enabled     = $false
        CurrentUrl  = $null
        ExpectedUrl = $null
        Updated     = $false
        Reason      = $null
    }

    try {
        $ConfigTable = Get-CIPPTable -TableName 'Config'
        $WebhookConfig = Get-CIPPAzDataTableEntity @ConfigTable -Filter "RowKey eq 'PartnerWebhookOnboarding'"
        if ($WebhookConfig.Enabled -ne $true) {
            $State.Reason = 'Automated onboarding is disabled - leaving the Partner Center subscription alone'
            Write-Information "[Partner-Webhook] $($State.Reason)"
            return $State
        }
        $State.Enabled = $true

        if ([string]::IsNullOrWhiteSpace($env:TenantID)) {
            $State.Reason = 'No partner tenant is configured yet - nothing to reconcile'
            Write-Information "[Partner-Webhook] $($State.Reason)"
            return $State
        }

        $SiteState = Get-CIPPSiteHostname -IncludeStatus -NoFallback
        if (-not $SiteState.Discovered -or [string]::IsNullOrWhiteSpace($SiteState.PreferredHostname)) {
            $State.Reason = "Bound hostnames could not be enumerated - not rewriting an external registration on a guess: $($SiteState.Error)"
            Write-Information "[Partner-Webhook] $($State.Reason)"
            return $State
        }

        $Hostname = $SiteState.PreferredHostname
        $State.ExpectedUrl = "https://$Hostname/api/PublicWebhooks?CIPPID=$($env:TenantID)&Type=PartnerCenter"

        # Read before write, in its own guard: if Partner Center cannot be reached we must not fall
        # through and "repair" a subscription whose current state we never established.
        try {
            $Existing = New-GraphGetRequest -uri 'https://api.partnercenter.microsoft.com/webhooks/v1/registration' -tenantid $env:TenantID -NoAuthCheck $true -scope 'https://api.partnercenter.microsoft.com/.default'
        } catch {
            $State.Reason = "Could not read the current Partner Center subscription - skipping: $($_.Exception.Message)"
            Write-Information "[Partner-Webhook] $($State.Reason)"
            return $State
        }
        $State.CurrentUrl = $Existing.webhookUrl

        if ($Existing.webhookUrl -eq $State.ExpectedUrl) {
            $State.Reason = "Partner Center already points at $($State.ExpectedUrl)"
            Write-Information "[Partner-Webhook] $($State.Reason)"
            return $State
        }

        if ($SiteState.CustomHostnames.Count -gt 1) {
            Write-Information "[Partner-Webhook] $($SiteState.CustomHostnames.Count) custom domains bound ($($SiteState.CustomHostnames -join ', ')) - registering against the first, '$Hostname'"
        }
        Write-Information "[Partner-Webhook] Subscription points at '$($Existing.webhookUrl)' but this instance is published on '$Hostname' - re-registering"

        # Pass the registered events back in, or the re-registration drops everything the admin
        # selected down to the two events New-CIPPGraphSubscription always adds.
        $EventTypes = @($Existing.webhookEvents)
        $Result = New-CIPPGraphSubscription -PartnerCenter -BaseURL $Hostname -EventType $EventTypes -APIName 'Partner Webhook Reconciliation'

        # New-CIPPGraphSubscription reports its own failures as a returned string rather than throwing
        $State.Reason = [string]$Result
        $State.Updated = $State.Reason -notmatch '^Failed'
        Write-Information "[Partner-Webhook] $($State.Reason)"
    } catch {
        $State.Reason = "Partner Center webhook reconciliation failed (non-fatal): $($_.Exception.Message)"
        Write-Information "[Partner-Webhook] $($State.Reason)"
    }

    return $State
}
