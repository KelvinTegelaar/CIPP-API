Function Invoke-ListRetentionCompliancePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.RetentionCompliancePolicy.Read
    .DESCRIPTION
        Lists retention compliance policies and their associated rules from the Security & Compliance Center.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.tenantFilter

    # Get-RetentionCompliancePolicy only populates the per-location properties (ExchangeLocation, ...) when
    # -DistributionDetail is set. Without it the flat 'Workload' string it returns is a fixed superset
    # ('Exchange, SharePoint, OneDriveForBusiness, Skype, ModernGroup, DynamicScope') that does not reflect
    # the policy's real scope, so we derive the scope from the populated location fields instead.
    $LocationLabels = [ordered]@{
        ExchangeLocation      = 'Exchange'
        SharePointLocation    = 'SharePoint'
        OneDriveLocation      = 'OneDrive'
        ModernGroupLocation   = 'Microsoft 365 Groups'
        TeamsChatLocation     = 'Teams Chats'
        TeamsChannelLocation  = 'Teams Channels'
        SkypeLocation         = 'Skype'
        PublicFolderLocation  = 'Public Folders'
        AdaptiveScopeLocation = 'Adaptive Scope'
    }

    try {
        # Teams-scoped retention policies are not returned by the default call - they require -TeamsPolicyOnly.
        # Fetch both sets (with distribution detail for the real location data) and merge, de-duped by Guid.
        $Policies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionCompliancePolicy' -cmdParams @{ DistributionDetail = $true } -Compliance -AsApp | Select-Object * -ExcludeProperty *odata*, *data.type*
        $TeamsPolicies = try {
            New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionCompliancePolicy' -cmdParams @{ DistributionDetail = $true; TeamsPolicyOnly = $true } -Compliance -AsApp | Select-Object * -ExcludeProperty *odata*, *data.type*
        } catch { @() }

        $SeenGuids = [System.Collections.Generic.HashSet[string]]::new()
        $AllPolicies = @(@($Policies) + @($TeamsPolicies) | Where-Object { $_ -and $SeenGuids.Add([string]$_.Guid) })

        $Rules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionComplianceRule' -Compliance -AsApp | Select-Object * -ExcludeProperty *odata*, *data.type*

        $GraphRequest = foreach ($Policy in $AllPolicies) {
            # Get-RetentionComplianceRule reports its parent policy via the policy Guid, not the policy Name.
            $PolicyRules = @($Rules | Where-Object { $_.Policy -eq $Policy.Guid })
            $PrimaryRule = $PolicyRules | Select-Object -First 1

            # Real scope is the set of location fields that actually carry a value.
            $Locations = foreach ($Field in $LocationLabels.Keys) {
                if (@($Policy.$Field).Where({ $_ }).Count -gt 0) { $LocationLabels[$Field] }
            }

            $RetentionDuration = if ($PrimaryRule) {
                if ([string]::IsNullOrEmpty([string]$PrimaryRule.RetentionDuration) -or $PrimaryRule.RetentionDuration -eq 'Unlimited') { 'Unlimited' } else { $PrimaryRule.RetentionDuration }
            } else { $null }

            # Note: Get-RetentionCompliancePolicy -DistributionDetail returns its own (empty) 'Locations'
            # property, so the derived scope summary is exposed as 'ScopedLocations' to avoid the collision
            # (Select-Object silently drops a computed property whose name already exists on the object).
            $Policy | Select-Object *,
            @{l = 'AssociatedRules'; e = { $PolicyRules } },
            @{l = 'RuleCount'; e = { $PolicyRules.Count } },
            @{l = 'ScopedLocations'; e = { @($Locations) -join ', ' } },
            @{l = 'RetentionAction'; e = { $PrimaryRule.RetentionComplianceAction } },
            @{l = 'RetentionDuration'; e = { $RetentionDuration } }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
