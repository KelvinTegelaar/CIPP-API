function Invoke-CIPPStandardAdminSSPR {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AdminSSPR
    .SYNOPSIS
        (Label) Set administrator Self-Service Password Reset state
    .DESCRIPTION
        (Helptext) Controls whether administrators are allowed to use Self-Service Password Reset through the Microsoft Entra authorization policy.
        (DocsDescription) Configures the allowedToUseSSPR property on the Microsoft Entra authorization policy. Microsoft documents this property as controlling whether administrators of the tenant can use Self-Service Password Reset. Use this standard to explicitly enable or disable administrator SSPR based on your security policy.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "EIDSCA.AP01"
            "EIDSCAAP01"
            "ZTNA21842"
        EXECUTIVETEXT
            Controls whether tenant administrators can reset their own passwords through Self-Service Password Reset. Disabling this capability forces privileged accounts through more controlled recovery processes and reduces the risk of self-service recovery being misused on administrative identities.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Select value","name":"standards.AdminSSPR.state","options":[{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2026-04-21
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthorizationPolicy
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    $StateValue = $Settings.state.value ?? $Settings.state
    if ([string]::IsNullOrWhiteSpace($StateValue)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'AdminSSPR: Invalid state parameter set.' -sev Error
        return
    }

    switch ($StateValue.ToLowerInvariant()) {
        'enabled' {
            $DesiredValue = $true
            $DesiredLabel = 'enabled'
        }
        'disabled' {
            $DesiredValue = $false
            $DesiredLabel = 'disabled'
        }
        default {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "AdminSSPR: Unsupported state value '$StateValue'." -sev Error
            return
        }
    }

    try {
        $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not get the AdminSSPR state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    $CurrentStateValue = [bool]$CurrentState.allowedToUseSSPR
    $StateIsCorrect = ($CurrentStateValue -eq $DesiredValue)

    $CurrentValue = [PSCustomObject]@{
        allowedToUseSSPR = $CurrentStateValue
    }
    $ExpectedValue = [PSCustomObject]@{
        allowedToUseSSPR = $DesiredValue
    }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Administrator SSPR is already $DesiredLabel." -sev Info
        } else {
            try {
                $Body = @{ allowedToUseSSPR = $DesiredValue } | ConvertTo-Json -Compress -Depth 10
                $null = New-GraphPOSTRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $Tenant -Type PATCH -Body $Body
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully set administrator SSPR to $DesiredLabel." -sev Info

                $CurrentState.allowedToUseSSPR = $DesiredValue
                $CurrentStateValue = $DesiredValue
                $StateIsCorrect = $true
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set administrator SSPR to $DesiredLabel. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Administrator SSPR is $DesiredLabel as configured." -sev Info
        } else {
            $CurrentLabel = if ($CurrentStateValue) { 'enabled' } else { 'disabled' }
            $AlertMessage = "Administrator SSPR is currently $CurrentLabel but should be $DesiredLabel."
            Write-StandardsAlert -message $AlertMessage -object $CurrentState -tenant $Tenant -standardName 'AdminSSPR' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message $AlertMessage -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.AdminSSPR' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'AdminSSPR' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
