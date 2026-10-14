function Test-CIPPIntuneCatalogPayload {
    <#
    .SYNOPSIS
        Structural checks for a Settings Catalog policy payload.
    .DESCRIPTION
        Walks the setting tree and returns finding objects for what would stop the policy deploying.
        Structural checks always run. IncludeCatalogChecks also resolves each setting against
        Get-CIPPIntuneDefinitionIndex: unknown settings and options are warnings (the catalog lags
        Intune), collection size bounds are errors (Intune rejects the whole policy).
    .EXAMPLE
        Test-CIPPIntuneCatalogPayload -Policy $Policy -IncludeCatalogChecks
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory = $true)]
        $Policy,
        [switch]$IncludeCatalogChecks
    )

    $Findings = [System.Collections.Generic.List[pscustomobject]]::new()
    function Add-Finding([string]$Severity, [string]$Code, [string]$Path, [string]$Message) {
        $Findings.Add([pscustomobject]@{ Severity = $Severity; Code = $Code; Path = $Path; Message = $Message })
    }

    if ($Policy.PSObject.Properties.Name -notcontains 'settings') {
        Add-Finding 'Error' 'MissingSettings' 'settings' 'A Settings Catalog policy must carry a settings array.'
        return @($Findings)
    }
    $Settings = @($Policy.settings)
    if ($Settings.Count -eq 0) {
        Add-Finding 'Warning' 'EmptySettings' 'settings' 'The policy has no settings, so it would deploy as an empty policy.'
        return @($Findings)
    }

    $Catalog = $IncludeCatalogChecks ? (Get-CIPPIntuneDefinitionIndex) : $null

    function Test-SettingInstance($Instance, [string]$Path) {
        if (-not $Instance) { return }
        $Names = $Instance.PSObject.Properties.Name

        if (-not $Instance.'@odata.type') {
            Add-Finding 'Error' 'MissingSettingODataType' $Path 'Setting instance is missing @odata.type.'
        }
        $DefinitionId = $Instance.settingDefinitionId
        $Definition = $null
        if ([string]::IsNullOrWhiteSpace($DefinitionId)) {
            Add-Finding 'Error' 'MissingSettingDefinitionId' $Path 'Setting instance is missing settingDefinitionId.'
        } elseif ($Catalog) {
            $Definition = $Catalog[$DefinitionId]
            if (-not $Definition) {
                Add-Finding 'Warning' 'UnknownSetting' $Path "Setting '$DefinitionId' is not in the shipped Intune catalog. It may be retired, or newer than the catalog."
            }
        }

        if ($Names -contains 'choiceSettingValue' -and $Instance.choiceSettingValue) {
            $Value = $Instance.choiceSettingValue.value
            if ($null -eq $Value) {
                Add-Finding 'Error' 'MissingChoiceValue' "$Path.choiceSettingValue" 'Choice setting has no value.'
            } elseif ($Definition.options -and $Value -notmatch '^%[^%]+%$' -and -not $Definition.options.ContainsKey("$Value")) {
                Add-Finding 'Warning' 'UnknownChoiceValue' "$Path.choiceSettingValue" "Value '$Value' is not one of the options the catalog lists for '$DefinitionId'."
            }
            if ($null -ne $Value -and $Definition.requiredChildIds) {
                $Present = @(@($Instance.choiceSettingValue.children).ForEach({ $_.settingDefinitionId }))
                foreach ($ChildId in @($Definition.requiredChildIds["$Value"]).Where({ $_ -and $Present -notcontains $_ })) {
                    Add-Finding 'Error' 'MissingRequiredChild' "$Path.choiceSettingValue" "'$DefinitionId' is set to '$Value', which requires '$ChildId'; Intune rejects the policy without it."
                }
            }
            $Index = 0
            foreach ($Child in @($Instance.choiceSettingValue.children)) {
                Test-SettingInstance $Child "$Path.choiceSettingValue.children[$Index]"
                $Index++
            }
        }

        if ($Names -contains 'simpleSettingValue' -and $Instance.simpleSettingValue -and -not $Instance.simpleSettingValue.'@odata.type') {
            Add-Finding 'Error' 'MissingValueODataType' "$Path.simpleSettingValue" 'Simple setting value is missing @odata.type.'
        }

        if ($Names -contains 'simpleSettingCollectionValue') {
            if ($null -eq $Instance.simpleSettingCollectionValue -or @($Instance.simpleSettingCollectionValue).Count -eq 0) {
                Add-Finding 'Error' 'EmptyCollectionValue' "$Path.simpleSettingCollectionValue" "'$DefinitionId' has no entries; Intune rejects an empty collection."
            }
            $Index = 0
            foreach ($Entry in @($Instance.simpleSettingCollectionValue)) {
                if (-not $Entry.'@odata.type') {
                    Add-Finding 'Error' 'MissingValueODataType' "$Path.simpleSettingCollectionValue[$Index]" 'Simple setting collection entry is missing @odata.type.'
                }
                $Index++
            }
        }

        foreach ($Property in 'groupSettingCollectionValue', 'choiceSettingCollectionValue') {
            if ($Names -notcontains $Property) { continue }
            $Entries = @($Instance.$Property)
            if ($Property -eq 'choiceSettingCollectionValue' -and ($null -eq $Instance.$Property -or $Entries.Count -eq 0)) {
                Add-Finding 'Error' 'EmptyCollectionValue' "$Path.$Property" "'$DefinitionId' has no entries; Intune rejects an empty collection."
            }

            # ConvertFrom-Json types small whole numbers as Int32 or Int64, so cast rather than type-test.
            if ($Definition) {
                $Maximum = $null -ne $Definition.maximumCount ? [int]$Definition.maximumCount : 0
                $Minimum = $null -ne $Definition.minimumCount ? [int]$Definition.minimumCount : 0
                if ($Maximum -gt 0 -and $Entries.Count -gt $Maximum) {
                    Add-Finding 'Error' 'TooManyCollectionEntries' "$Path.$Property" "'$DefinitionId' holds $($Entries.Count) entries but Intune allows at most $Maximum."
                }
                if ($Entries.Count -lt $Minimum) {
                    Add-Finding 'Error' 'TooFewCollectionEntries' "$Path.$Property" "'$DefinitionId' holds $($Entries.Count) entries but Intune requires at least $Minimum."
                }
            }

            $Index = 0
            foreach ($Entry in $Entries) {
                $EntryPath = "$Path.$Property[$Index]"
                if ($Property -eq 'choiceSettingCollectionValue' -and $null -eq $Entry.value) {
                    Add-Finding 'Error' 'MissingChoiceValue' $EntryPath 'Choice collection entry has no value.'
                }
                if ($Property -eq 'choiceSettingCollectionValue' -and $null -ne $Entry.value -and $Definition.requiredChildIds) {
                    $Present = @(@($Entry.children).ForEach({ $_.settingDefinitionId }))
                    foreach ($ChildId in @($Definition.requiredChildIds["$($Entry.value)"]).Where({ $_ -and $Present -notcontains $_ })) {
                        Add-Finding 'Error' 'MissingRequiredChild' $EntryPath "'$DefinitionId' entry '$($Entry.value)' requires '$ChildId'; Intune rejects the policy without it."
                    }
                }
                if ($Property -eq 'groupSettingCollectionValue' -and @($Entry.children).Count -eq 0) {
                    Add-Finding 'Error' 'EmptyGroupEntry' $EntryPath "'$DefinitionId' has a group entry with no settings in it; Intune rejects the whole policy."
                }
                $ChildIndex = 0
                foreach ($Child in @($Entry.children)) {
                    Test-SettingInstance $Child "$EntryPath.children[$ChildIndex]"
                    $ChildIndex++
                }
                $Index++
            }
        }

        if ($Names -contains 'groupSettingValue' -and $Instance.groupSettingValue) {
            if (@($Instance.groupSettingValue.children).Count -eq 0) {
                Add-Finding 'Error' 'EmptyGroupEntry' "$Path.groupSettingValue" "'$DefinitionId' is a group with no settings in it; Intune rejects the whole policy."
            }
            $ChildIndex = 0
            foreach ($Child in @($Instance.groupSettingValue.children)) {
                Test-SettingInstance $Child "$Path.groupSettingValue.children[$ChildIndex]"
                $ChildIndex++
            }
        }
    }

    $Index = 0
    foreach ($Setting in $Settings) {
        if (-not $Setting.settingInstance) {
            Add-Finding 'Error' 'MissingSettingInstance' "settings[$Index]" 'Setting entry has no settingInstance.'
        } else {
            Test-SettingInstance $Setting.settingInstance "settings[$Index].settingInstance"
        }
        $Index++
    }

    return @($Findings)
}
