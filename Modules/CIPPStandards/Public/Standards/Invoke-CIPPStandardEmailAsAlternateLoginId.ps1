function Invoke-CIPPStandardEmailAsAlternateLoginId {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EmailAsAlternateLoginId
    .SYNOPSIS
        (Label) Configure Email as alternate login ID
    .DESCRIPTION
        (Helptext) Configures the tenant-wide Email as alternate login ID setting in Home Realm Discovery policy.
        (DocsDescription) Sets the Home Realm Discovery policy AlternateIdLogin setting to enable or disable using email as an alternate sign-in ID.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        EXECUTIVETEXT
            Controls whether users can sign in with email as an alternate identifier, allowing organizations to align sign-in behavior with their identity strategy and reduce authentication ambiguity.
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.EmailAsAlternateLoginId.Enabled","label":"Enable Email as Alternate Login ID","defaultValue":false}
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-06-03
        POWERSHELLEQUIVALENT
            Invoke-MgGraphRequest https://graph.microsoft.com/v1.0/policies/homeRealmDiscoveryPolicies/
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    $DesiredEnabledValue = $Settings.Enabled.value ?? $Settings.Enabled ?? $false
    $DesiredEnabled = if ($DesiredEnabledValue -is [bool]) {
        $DesiredEnabledValue
    } elseif ($DesiredEnabledValue -is [string]) {
        $DesiredEnabledValue -eq 'true'
    } else {
        [bool]$DesiredEnabledValue
    }
    $DesiredStatus = if ($DesiredEnabled) { 'enabled' } else { 'disabled' }

    try {
        $Policies = @(New-GraphGetRequest -Uri 'https://graph.microsoft.com/v1.0/policies/homeRealmDiscoveryPolicies' -tenantid $Tenant)
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the EmailAsAlternateLoginId state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }

    $CurrentPolicy = @($Policies | Where-Object { $_.isOrganizationDefault -eq $true }) | Select-Object -First 1
    $CurrentDefinition = if ($CurrentPolicy.definition) {
        ($CurrentPolicy.definition | Select-Object -First 1) | ConvertFrom-Json -ErrorAction SilentlyContinue
    } else {
        $null
    }
    $CurrentEnabledRaw = $CurrentDefinition.HomeRealmDiscoveryPolicy.AlternateIdLogin.Enabled
    $PolicyExists = $null -ne $CurrentPolicy
    $HasExplicitSetting = $null -ne $CurrentEnabledRaw
    $CurrentEnabled = if ($null -eq $CurrentEnabledRaw) { $false } else { [bool]$CurrentEnabledRaw }
    $StateIsCorrect = $PolicyExists -and $HasExplicitSetting -and ($CurrentEnabled -eq $DesiredEnabled)

    $CurrentValue = [PSCustomObject]@{
        AlternateIdLoginEnabled = $CurrentEnabled
        PolicyExists            = $PolicyExists
        HasExplicitSetting      = $HasExplicitSetting
    }
    $ExpectedValue = [PSCustomObject]@{
        AlternateIdLoginEnabled = $DesiredEnabled
        PolicyExists            = $true
        HasExplicitSetting      = $true
    }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Email as alternate login ID is already $DesiredStatus." -sev Info
        } else {
            try {
                $PolicyDefinition = @{
                    HomeRealmDiscoveryPolicy = @{
                        AlternateIdLogin = @{
                            Enabled = $DesiredEnabled
                        }
                    }
                } | ConvertTo-Json -Depth 10 -Compress

                $Body = @{
                    definition            = @($PolicyDefinition)
                    isOrganizationDefault = $true
                    displayName           = 'HomeRealmDiscoveryPolicy'
                } | ConvertTo-Json -Depth 10 -Compress

                if ($PolicyExists) {
                    $RequestUri = "https://graph.microsoft.com/v1.0/policies/homeRealmDiscoveryPolicies/$($CurrentPolicy.id)"
                    $RequestType = 'PATCH'
                } else {
                    $RequestUri = 'https://graph.microsoft.com/v1.0/policies/homeRealmDiscoveryPolicies/'
                    $RequestType = 'POST'
                }

                New-GraphPostRequest -tenantid $Tenant -Uri $RequestUri -Type $RequestType -Body $Body | Out-Null
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set Email as alternate login ID to $DesiredStatus." -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Email as alternate login ID to $DesiredStatus. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Email as alternate login ID is $DesiredStatus." -sev Info
        } else {
            Write-StandardsAlert -message "Email as alternate login ID is not $DesiredStatus." -object $CurrentValue -tenant $Tenant -standardName 'EmailAsAlternateLoginId' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Email as alternate login ID is not $DesiredStatus." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.EmailAsAlternateLoginId' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'EmailAsAlternateLoginId' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
