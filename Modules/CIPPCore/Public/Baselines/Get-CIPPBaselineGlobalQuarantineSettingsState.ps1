function Get-CIPPBaselineGlobalQuarantineSettingsState {
    <#
    .SYNOPSIS
        Prepare hook for GlobalQuarantineSettings: sender/subject/disclaimer branding on the
        global quarantine policy.
    .DESCRIPTION
        The per-language text fields grade as CONTAINS: the policy stores one value per
        configured language and the classic checked the configured text is among them,
        because remediation writes the same text into every language slot.

        Only configured fields grade. The classic graded unset fields too - '-contains
        $null' is false whenever any value exists - which made an unset optional field
        permanent drift and remediation would then write nulls over real branding. Grading
        only what the operator expressed is the intended behaviour of those optional fields.

        The organization branding switch is a real boolean and always grades.

        The policy's language list is carried for the executor: the write must fan the text
        out across exactly the languages the tenant has configured.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policy = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoGlobalQuarantinePolicy') | Select-Object -First 1
    if (-not $Policy) { return @{ Current = $null } }

    $V = $Item.Variables
    $Expected = [PSCustomObject]@{}
    $Current = [PSCustomObject]@{}

    $TextFields = @(
        @{ Name = 'senderNamePresent'; Value = "$($V.SenderName)"; CurrentList = @($Policy.MultiLanguageSenderName) }
        @{ Name = 'customSubjectPresent'; Value = "$($V.CustomSubject)"; CurrentList = @($Policy.ESNCustomSubject) }
        @{ Name = 'customDisclaimerPresent'; Value = "$($V.CustomDisclaimer)"; CurrentList = @($Policy.MultiLanguageCustomDisclaimer) }
    )
    foreach ($Field in $TextFields) {
        if ([string]::IsNullOrWhiteSpace($Field.Value)) { continue }
        $Expected | Add-Member -NotePropertyName $Field.Name -NotePropertyValue $true
        $Current | Add-Member -NotePropertyName $Field.Name -NotePropertyValue ([bool]($Field.CurrentList -contains $Field.Value))
    }
    if (-not [string]::IsNullOrWhiteSpace("$($V.FromAddress)")) {
        $Expected | Add-Member -NotePropertyName 'fromAddress' -NotePropertyValue "$($V.FromAddress)"
        $Current | Add-Member -NotePropertyName 'fromAddress' -NotePropertyValue "$($Policy.EndUserSpamNotificationCustomFromAddress)"
    }
    $Expected | Add-Member -NotePropertyName 'organizationBrandingEnabled' -NotePropertyValue ([bool]($V.OrganizationBrandingEnabled -eq $true))
    $Current | Add-Member -NotePropertyName 'organizationBrandingEnabled' -NotePropertyValue ([bool]$Policy.OrganizationBrandingEnabled)

    # Carried for the executor: the write fans texts across these languages, and the
    # Microsoft default policy cannot be modified - it must be replaced by name. The
    # CURRENT per-language arrays ride along because Exchange requires all three arrays
    # on every write with counts equal to the language count - an unconfigured field must
    # resend the tenant's existing values, not omit the array or null it.
    $Languages = @($Policy.MultiLanguageSetting)
    if ($Languages.Count -eq 0) { $Languages = @('Default') }
    $Current | Add-Member -NotePropertyName 'languages' -NotePropertyValue @($Languages)
    $Current | Add-Member -NotePropertyName 'currentSenderNames' -NotePropertyValue @($Policy.MultiLanguageSenderName)
    $Current | Add-Member -NotePropertyName 'currentSubjects' -NotePropertyValue @($Policy.ESNCustomSubject)
    $Current | Add-Member -NotePropertyName 'currentDisclaimers' -NotePropertyValue @($Policy.MultiLanguageCustomDisclaimer)
    $Current | Add-Member -NotePropertyName 'policyName' -NotePropertyValue "$($Policy.Name)"
    $Current | Add-Member -NotePropertyName 'policyIdentity' -NotePropertyValue "$($Policy.Identity)"

    @{ Expected = $Expected; Current = $Current }
}
