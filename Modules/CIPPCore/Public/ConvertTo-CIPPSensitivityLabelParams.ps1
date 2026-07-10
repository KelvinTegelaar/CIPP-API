function ConvertTo-CIPPSensitivityLabelParams {
    <#
    .SYNOPSIS
        Normalize a sensitivity label template/object into the flat parameter shape that New-Label/Set-Label expect.
    .DESCRIPTION
        Get-Label (the read shape) does not expose flat Encryption*/Apply* properties. Instead it encodes
        encryption, content marking and watermarking inside the 'LabelActions' array, e.g.

            { "Type":"encrypt", "SubType":null, "Settings":[ {"Key":"protectiontype","Value":"userdefined"}, ... ] }
            { "Type":"applycontentmarking", "SubType":"footer", "Settings":[ {"Key":"text","Value":"..."}, ... ] }

        New-Label/Set-Label (the write shape) instead take flat 'Apply*'/'Encryption*' parameters. This
        function bridges the two: when a label object carries 'LabelActions' it expands those actions into
        the flat parameters and drops the read-only 'LabelActions'/'Settings'/'LocaleSettings'/'Conditions'
        arrays (which are not valid input in their read form). A flat object (manual JSON authored against
        the deploy schema) has no 'LabelActions' and passes through unchanged.

        Applied -AdvancedSettings values (e.g. a custom label color) are only readable through the same
        read-only 'Settings' array, so before dropping it the writable advanced settings are lifted into
        an 'AdvancedSettings' dictionary that New-/Set-Label accept. An explicit 'AdvancedSettings' value
        already on the template wins over captured values.

        Deploy-time validation/allowlisting still happens in Set-CIPPSensitivityLabel via
        Get-CIPPSensitivityLabelField; this function only reshapes.
    .PARAMETER Label
        The label template/object to normalize (a Get-Label object, a stored template, or flat manual JSON).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Label
    )

    # A captured Get-Label object always has a LabelActions property (even if empty); flat manual JSON does not.
    $HasActions = [bool]$Label.PSObject.Properties['LabelActions']
    # Read-shape arrays that are not valid New-/Set-Label input - dropped when reshaping a captured label.
    $ReadShapeArrays = @('LabelActions', 'Settings', 'LocaleSettings', 'Conditions')

    $Flat = [ordered]@{}
    foreach ($Prop in $Label.PSObject.Properties) {
        if ($HasActions -and $Prop.Name -in $ReadShapeArrays) { continue }
        $Flat[$Prop.Name] = $Prop.Value
    }

    if (-not $HasActions) {
        return [pscustomobject]$Flat
    }

    # Writable advanced settings that Get-Label only reports inside the read-only Settings array
    # ([key, value] pairs). The rest of Settings is system metadata (displayname, contenttype,
    # tooltip, ...) that must not be echoed back to New-/Set-Label. Extend this list as more
    # -AdvancedSettings keys gain first-class support.
    $WritableAdvancedSettings = @('color')
    $CapturedAdvanced = @{}
    foreach ($Entry in @($Label.Settings)) {
        if ($null -eq $Entry) { continue }
        $Key = $null
        $Value = $null
        if ($Entry -isnot [string] -and $Entry.PSObject.Properties['Key']) {
            $Key = $Entry.Key
            $Value = $Entry.Value
        } elseif ("$Entry" -match '^\[\s*(.+?)\s*,\s*(.*?)\s*\]$') {
            # Get-Label serializes each entry as the string '[key, value]'
            $Key = $Matches[1]
            $Value = $Matches[2]
        }
        if ($Key -and $Key.ToLower() -in $WritableAdvancedSettings -and -not [string]::IsNullOrWhiteSpace("$Value")) {
            $CapturedAdvanced[$Key.ToLower()] = "$Value"
        }
    }
    if ($CapturedAdvanced.Count -gt 0) {
        # Explicit AdvancedSettings on the template win over values captured from Settings.
        $Explicit = $Flat['AdvancedSettings']
        if ($Explicit -is [System.Collections.IDictionary]) {
            foreach ($ExplicitKey in @($Explicit.Keys)) { $CapturedAdvanced[$ExplicitKey] = $Explicit[$ExplicitKey] }
        } elseif ($null -ne $Explicit) {
            foreach ($ExplicitProp in $Explicit.PSObject.Properties) { $CapturedAdvanced[$ExplicitProp.Name] = $ExplicitProp.Value }
        }
        $Flat['AdvancedSettings'] = $CapturedAdvanced
    }

    foreach ($Raw in @($Label.LabelActions)) {
        if ($null -eq $Raw) { continue }
        $Action = if ($Raw -is [string]) { $Raw | ConvertFrom-Json } else { $Raw }

        $Set = @{}
        foreach ($KV in $Action.Settings) { $Set[$KV.Key] = $KV.Value }
        $Enabled = ($Set['disabled'] -ne 'true')

        switch ($Action.Type) {
            'encrypt' {
                $Flat['EncryptionEnabled'] = $Enabled
                if (-not $Enabled) { break }

                $ProtectionType = "$($Set['protectiontype'])".ToLower()
                if ($ProtectionType -eq 'template') {
                    $Flat['EncryptionProtectionType'] = 'Template'
                    if ($Set['templateid']) { $Flat['EncryptionTemplateId'] = $Set['templateid'] }
                    if ($Set.ContainsKey('contentexpiredondateindaysornever')) { $Flat['EncryptionContentExpiredOnDateInDaysOrNever'] = $Set['contentexpiredondateindaysornever'] }
                    if ($Set.ContainsKey('offlineaccessdays')) { $Flat['EncryptionOfflineAccessDays'] = [int]$Set['offlineaccessdays'] }
                } else {
                    $Flat['EncryptionProtectionType'] = 'UserDefined'
                    if ($Set.ContainsKey('donotforward')) { $Flat['EncryptionDoNotForward'] = ($Set['donotforward'] -eq 'true') }
                    if ($Set.ContainsKey('encryptonly')) { $Flat['EncryptionEncryptOnly'] = ($Set['encryptonly'] -eq 'true') }
                    if ($Set.ContainsKey('promptuser')) { $Flat['EncryptionPromptUser'] = ($Set['promptuser'] -eq 'true') }
                }
            }
            'applycontentmarking' {
                $Prefix = switch ("$($Action.SubType)".ToLower()) {
                    'header' { 'ApplyContentMarkingHeader' }
                    'footer' { 'ApplyContentMarkingFooter' }
                    'watermark' { 'ApplyWaterMarking' }
                    default { $null }
                }
                if (-not $Prefix) { break }

                $Flat["${Prefix}Enabled"] = $Enabled
                if ($Set['text']) { $Flat["${Prefix}Text"] = $Set['text'] }
                if ($Set['fontcolor']) { $Flat["${Prefix}FontColor"] = $Set['fontcolor'] }
                if ($Set['fontname']) { $Flat["${Prefix}FontName"] = $Set['fontname'] }
                if ($Set.ContainsKey('fontsize') -and "$($Set['fontsize'])".Trim()) { $Flat["${Prefix}FontSize"] = [int]$Set['fontsize'] }
                if ($Prefix -eq 'ApplyWaterMarking') {
                    if ($Set['layout']) { $Flat['ApplyWaterMarkingLayout'] = $Set['layout'] }
                } else {
                    if ($Set['alignment']) { $Flat["${Prefix}Alignment"] = $Set['alignment'] }
                    if ($Action.SubType -eq 'footer' -and $Set.ContainsKey('margin') -and "$($Set['margin'])".Trim()) { $Flat["${Prefix}Margin"] = [int]$Set['margin'] }
                }
            }
            'applywatermarking' {
                $Flat['ApplyWaterMarkingEnabled'] = $Enabled
                if ($Set['text']) { $Flat['ApplyWaterMarkingText'] = $Set['text'] }
                if ($Set['fontcolor']) { $Flat['ApplyWaterMarkingFontColor'] = $Set['fontcolor'] }
                if ($Set['fontname']) { $Flat['ApplyWaterMarkingFontName'] = $Set['fontname'] }
                if ($Set.ContainsKey('fontsize') -and "$($Set['fontsize'])".Trim()) { $Flat['ApplyWaterMarkingFontSize'] = [int]$Set['fontsize'] }
                if ($Set['layout']) { $Flat['ApplyWaterMarkingLayout'] = $Set['layout'] }
            }
            'protectgroup' {
                $Flat['SiteAndGroupProtectionEnabled'] = $Enabled
                if ($Set['privacy']) { $Flat['SiteAndGroupProtectionPrivacy'] = $Set['privacy'] }
                if ($Set.ContainsKey('allowaccesstoguestusers')) { $Flat['SiteAndGroupProtectionAllowAccessToGuestUsers'] = ($Set['allowaccesstoguestusers'] -eq 'true') }
                if ($Set.ContainsKey('allowemailfromguestusers')) { $Flat['SiteAndGroupProtectionAllowEmailFromGuestUsers'] = ($Set['allowemailfromguestusers'] -eq 'true') }
            }
        }
    }

    return [pscustomobject]$Flat
}
