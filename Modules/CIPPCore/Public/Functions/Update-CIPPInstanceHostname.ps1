function Update-CIPPInstanceHostname {
    <#
    .SYNOPSIS
        Reconciles the stored instance URL with the custom domain bound to this App Service.
    .DESCRIPTION
        Config/InstanceProperties/CIPPURL is what background work builds links from - scheduled
        notifications, drift emails, audit log downloads - and what the Partner Center webhook
        subscription is registered against. Nothing writes it on its own: it is set from whichever
        request happened to call Get-CIPPHostname -Save, so binding a new custom domain (or
        removing the old one) leaves it pointing at the previous URL until an admin notices and
        re-saves the automated onboarding page by hand.

        Running this at warmup makes the instance self-healing: ARM is asked which hostnames are
        actually bound, the first custom domain wins (falling back to the platform hostname when
        there is none), and the stored value is corrected if it drifted.

        A failed ARM lookup is NOT drift. Only an authoritative answer can tell a removed custom
        domain from an unreachable management endpoint, so anything less leaves the stored value
        alone - writing on a transient 403 would demote a working custom domain to the
        *.azurewebsites.net hostname and quietly break every link CIPP emails out.

        Never throws; warmup steps are soft-fail by design.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Update-CIPPInstanceHostname
    #>
    [CmdletBinding()]
    param()

    $State = [PSCustomObject]@{
        StoredHostname   = $null
        ResolvedHostname = $null
        CustomHostnames  = @()
        Updated          = $false
        Reason           = $null
    }

    try {
        $SiteState = Get-CIPPSiteHostname -IncludeStatus -NoFallback
        $State.CustomHostnames = @($SiteState.CustomHostnames)

        if (-not $SiteState.Discovered) {
            $State.Reason = "Bound hostnames could not be enumerated - leaving the stored instance URL alone: $($SiteState.Error)"
            Write-Information "[Instance-URL] $($State.Reason)"
            return $State
        }

        $Resolved = $SiteState.PreferredHostname
        if ([string]::IsNullOrWhiteSpace($Resolved)) {
            $State.Reason = 'ARM returned no usable hostname for this site - nothing to reconcile'
            Write-Information "[Instance-URL] $($State.Reason)"
            return $State
        }
        $State.ResolvedHostname = $Resolved

        if ($State.CustomHostnames.Count -gt 1) {
            Write-Information "[Instance-URL] $($State.CustomHostnames.Count) custom domains bound ($($State.CustomHostnames -join ', ')) - using the first, '$Resolved'"
        } elseif ($State.CustomHostnames.Count -eq 0) {
            Write-Information "[Instance-URL] No custom domain bound - using the platform hostname '$Resolved'"
        }

        $ConfigTable = Get-CIPPTable -TableName 'Config'
        $Stored = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
        $State.StoredHostname = $Stored.Value

        if ($Stored.Value -eq $Resolved) {
            $State.Reason = "Stored instance URL already matches the bound domain ($Resolved)"
            Write-Information "[Instance-URL] $($State.Reason)"
            return $State
        }

        $Entity = @{
            PartitionKey = 'InstanceProperties'
            RowKey       = 'CIPPURL'
            Value        = [string]$Resolved
        }
        Add-CIPPAzDataTableEntity @ConfigTable -Entity $Entity -Force

        $State.Updated = $true
        $State.Reason = "Updated stored instance URL from '$($Stored.Value)' to '$Resolved'"
        Write-Information "[Instance-URL] $($State.Reason)"
    } catch {
        $State.Reason = "Instance URL reconciliation failed (non-fatal): $($_.Exception.Message)"
        Write-Information "[Instance-URL] $($State.Reason)"
    }

    return $State
}
