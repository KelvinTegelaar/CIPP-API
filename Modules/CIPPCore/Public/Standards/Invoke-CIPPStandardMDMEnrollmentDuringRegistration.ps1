function Invoke-CIPPStandardMDMEnrollmentDuringRegistration {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) MDMEnrollmentDuringRegistration
    .SYNOPSIS
        (Label) Configure MDM enrollment when adding work or school account
    .DESCRIPTION
        (Helptext) Controls the "Allow my organization to manage my device" prompt when adding a work or school account on Windows. This setting determines whether automatic MDM enrollment occurs during account registration.
        (DocsDescription) Controls whether Windows shows the "Allow my organization to manage my device" prompt when users add a work or school account. When set to disabled, this setting prevents automatic MDM enrollment during the account registration flow, separating account registration from device enrollment. This is useful for environments where you want to allow users to add work accounts without triggering MDM enrollment.
    .NOTES
        CAT
            Intune Standards
        TAG
        EXECUTIVETEXT
            Controls automatic device management enrollment during work account setup. When disabled, users can add work accounts to their Windows devices without the prompt asking to allow organizational device management, preventing unintended MDM enrollments on personal or BYOD devices.
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.MDMEnrollmentDuringRegistration.disableEnrollment","label":"Disable MDM enrollment during registration"}
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-12-15
        POWERSHELLEQUIVALENT
            Graph API PATCH to mobileDeviceManagementPolicies
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'MDMEnrollmentDuringRegistration' -TenantFilter $Tenant -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1')

    if ($TestResult -eq $false) {
        return $true
    }

    try {
        $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/mobileDeviceManagementPolicies/0000000a-0000-0000-c000-000000000000' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get MDM enrollment during registration state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }

    # Get the current state - if the property doesn't exist, treat as false (default behavior)
    $CurrentState = [bool]$CurrentInfo.isMdmEnrollmentDuringRegistrationDisabled
    $DesiredState = [bool]$Settings.disableEnrollment
    $StateIsCorrect = $CurrentState -eq $DesiredState
    $stateText = $DesiredState ? 'disabled' : 'enabled'

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "MDM enrollment during registration is already $stateText" -sev Info
        } else {
            $GraphParam = @{
                tenantid = $Tenant
                Uri      = 'https://graph.microsoft.com/beta/policies/mobileDeviceManagementPolicies/0000000a-0000-0000-c000-000000000000'
                type     = 'PATCH'
                Body     = (@{'isMdmEnrollmentDuringRegistrationDisabled' = $DesiredState } | ConvertTo-Json)
            }

            try {
                New-GraphPostRequest @GraphParam
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully $stateText MDM enrollment during registration" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to configure MDM enrollment during registration. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "MDM enrollment during registration is $stateText as configured" -sev Info
        } else {
            Write-StandardsAlert -message "MDM enrollment during registration is not $stateText" -object @{isMdmEnrollmentDuringRegistrationDisabled = $CurrentState; desiredState = $DesiredState } -tenant $tenant -standardName 'MDMEnrollmentDuringRegistration' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "MDM enrollment during registration is not $stateText" -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            isMdmEnrollmentDuringRegistrationDisabled = $CurrentState
        }
        $ExpectedValue = @{
            isMdmEnrollmentDuringRegistrationDisabled = $DesiredState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.MDMEnrollmentDuringRegistration' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'MDMEnrollmentDuringRegistration' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
