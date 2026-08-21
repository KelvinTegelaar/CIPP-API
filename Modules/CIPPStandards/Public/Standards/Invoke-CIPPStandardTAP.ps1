function Invoke-CIPPStandardTAP {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TAP
    .SYNOPSIS
        (Label) Enable Temporary Access Passes (TAP)
    .DESCRIPTION
        (Helptext) Enable TAP with the specified configuration settings.
        (DocsDescription) Enables Temporary Access Pass generation for the tenant.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        APPLIESTOTEST
            "EIDSCAAT01"
            "EIDSCAAT02"
            "ZTNA21845"
            "ZTNA21846"
        EXECUTIVETEXT
            Enables temporary access passes that IT administrators can generate for employees who are locked out or need emergency access to systems. These time-limited passes provide a secure way to restore access without compromising long-term security policies.
        ADDEDCOMPONENT
            {"type":"number","name":"standards.TAP.MinimumLifetime","label":"Minimum Lifetime (minutes)","defaultValue":60}
            {"type":"number","name":"standards.TAP.MaximumLifetime","label":"Maximum Lifetime (minutes)","defaultValue":480}
            {"type":"number","name":"standards.TAP.DefaultLifetime","label":"Default Lifetime (minutes)","defaultValue":60}
            {"type":"number","name":"standards.TAP.TAPLength","label":"Length (characters)","defaultValue":8}
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Number of Times Usable","name":"standards.TAP.config","options":[{"label":"Only Once","value":"true"},{"label":"Multiple Logons","value":"false"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2022-03-15
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)
    
    # Get config values using null-coalescing operator
    $MinimumLifetime  = [int]($Settings.MinimumLifetime ?? 60)
    $MaximumLifetime  = [int]($Settings.MaximumLifetime ?? 480)
    $DefaultLifetime  = [int]($Settings.DefaultLifetime ?? 60)
    $TAPLength        = [int]($Settings.TAPLength ?? 8)
    $OneTimeUse       = $Settings.config.value ?? $Settings.config ?? 'true'
    $OneTimeUseBool   = [System.Convert]::ToBoolean($OneTimeUse)

    if ($MinimumLifetime -gt $MaximumLifetime) {
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "TAP: minimum lifetime ($MinimumLifetime) exceeds maximum lifetime ($MaximumLifetime). Skipping run, correct the standard configuration." -Sev Error
        return
    }
    
    if ($DefaultLifetime -lt $MinimumLifetime -or $DefaultLifetime -gt $MaximumLifetime) {
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "TAP: default lifetime ($DefaultLifetime) must fall between the minimum ($MinimumLifetime) and maximum ($MaximumLifetime). Skipping run, correct the standard configuration." -Sev Error
        return
    }

    try {
        $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/TemporaryAccessPass' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the TAP state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $StateIsCorrect = $CurrentState.state -eq 'enabled' -and
    [int]$CurrentState.minimumLifetimeInMinutes -eq $MinimumLifetime -and
    [int]$CurrentState.maximumLifetimeInMinutes -eq $MaximumLifetime -and
    [int]$CurrentState.defaultLifetimeInMinutes -eq $DefaultLifetime -and
    [int]$CurrentState.defaultLength -eq $TAPLength -and
    [System.Convert]::ToBoolean($CurrentState.isUsableOnce) -eq $OneTimeUseBool

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Temporary Access Pass policy already matches the desired state.' -sev Info
        } else {
            try {
                $PolicyConfig = @{
                  Tenant                 = $Tenant
                  APIName                = 'Standards'
                  AuthenticationMethodId = 'TemporaryAccessPass'
                  Enabled                = $true
                  TapMinimumLifetime     = $MinimumLifetime
                  TAPMaximumLifetime     = $MaximumLifetime
                  TAPDefaultLifeTime     = $DefaultLifetime
                  TAPDefaultLength       = $TAPLength
                  TAPisUsableOnce        = $OneTimeUseBool
                }

                Set-CIPPAuthenticationPolicy @PolicyConfig
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to configure Temporary Access Pass policy. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Temporary Access Pass policy is enabled and configured.' -sev Info
        } else {
            $Object = $CurrentState | Select-Object -Property state, isUsableOnce, defaultLifetimeInMinutes, defaultLength, maximumLifetimeInMinutes, minimumLifetimeInMinutes
            Write-StandardsAlert -message 'Temporary Access Pass policy is not enabled.' -object $Object -tenant $Tenant -standardName 'TAP' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Temporary Access Pass policy is not enabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'TemporaryAccessPass' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant

        $CurrentValue = @{
            state                    = $CurrentState.state
            minimumLifetimeInMinutes = [int]$CurrentState.minimumLifetimeInMinutes
            maximumLifetimeInMinutes = [int]$CurrentState.maximumLifetimeInMinutes
            defaultLifetimeInMinutes = [int]$CurrentState.defaultLifetimeInMinutes
            defaultLength            = [int]$CurrentState.defaultLength
            isUsableOnce             = [System.Convert]::ToBoolean($CurrentState.isUsableOnce)
        }

        $ExpectedValue = @{
            state                    = 'enabled'
            minimumLifetimeInMinutes = $MinimumLifetime
            maximumLifetimeInMinutes = $MaximumLifetime
            defaultLifetimeInMinutes = $DefaultLifetime
            defaultLength            = $TAPLength
            isUsableOnce             = $OneTimeUseBool
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.TAP' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}
