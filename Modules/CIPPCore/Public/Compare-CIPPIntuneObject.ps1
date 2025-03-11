function Compare-CIPPIntuneObject {
    <#
    .SYNOPSIS
    Compares two Intune objects and returns only the differences.

    .DESCRIPTION
    This function takes two Intune objects and performs a comparison, returning only the properties that differ.
    If no differences are found, it returns null.
    It's useful for identifying changes between template objects and existing policies.

    .PARAMETER ReferenceObject
    The reference Intune object to compare against.

    .PARAMETER DifferenceObject
    The Intune object to compare with the reference object.

    .PARAMETER ExcludeProperties
    Additional properties to exclude from the comparison.

    .EXAMPLE
    $template = Get-CIPPIntunePolicy -tenantFilter $Tenant -DisplayName "Template Policy" -TemplateType "Device"
    $existing = Get-CIPPIntunePolicy -tenantFilter $Tenant -DisplayName "Existing Policy" -TemplateType "Device"
    $differences = Compare-CIPPIntuneObject -ReferenceObject $template -DifferenceObject $existing

    .NOTES
    This function performs a comparison of objects, including nested properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ReferenceObject,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DifferenceObject,

        [Parameter(Mandatory = $false)]
        [string[]]$ExcludeProperties = @(),
        [Parameter(Mandatory = $false)]
        [string[]]$CompareType = @()
    )
    if ($CompareType -ne 'Catalog') {
        # Default properties to exclude from comparison
        $defaultExcludeProperties = @(
            'id',
            'createdDateTime',
            'lastModifiedDateTime',
            'supportsScopeTags',
            'modifiedDateTime',
            'version',
            'roleScopeTagIds',
            'settingCount',
            'creationSource',
            'priorityMetaData'
            'featureUpdatesWillBeRolledBack',
            'qualityUpdatesWillBeRolledBack',
            'qualityUpdatesPauseStartDate',
            'featureUpdatesPauseStartDate'
        )

        # Combine default and custom exclude properties
        $excludeProps = $defaultExcludeProperties + $ExcludeProperties

        # Create a list to store comparison results
        $compareProperties = [System.Collections.Generic.List[PSObject]]::new()

        # Clean up objects by removing excluded properties
        $obj1 = $ReferenceObject | Select-Object * -ExcludeProperty @($excludeProps | ForEach-Object { $_ })
        $obj2 = $DifferenceObject | Select-Object * -ExcludeProperty @($excludeProps | ForEach-Object { $_ })

        # Skip OData properties and excluded properties
        $skipProps = [System.Collections.Generic.List[string]]::new()
        foreach ($propName in ($obj1.PSObject.Properties | Select-Object Name).Name) {
            if ($propName -like '*@OData*' -or $propName -like '#microsoft.graph*' -or $excludeProps -contains $propName) {
                $skipProps.Add($propName)
            }
        }

        # Define core properties to compare first
        $coreProps = @('displayName', 'Description', 'Id')
        $postProps = @('Advertisements')
        $skipPropertiesToCompare = @()

        # Compare core properties
        foreach ($propName in $coreProps) {
            if (-not ($obj1.PSObject.Properties | Where-Object Name -EQ $propName)) {
                continue
            }
            $val1 = ($obj1.$propName | ConvertTo-Json -Depth 10)
            $val2 = ($obj2.$propName | ConvertTo-Json -Depth 10)

            $value1 = if ($null -eq $val1) { '' } else { $val1.ToString().Trim('"') }
            $value2 = if ($null -eq $val2) { '' } else { $val2.ToString().Trim('"') }

            $match = ($value1 -eq $value2)

            if (-not $match) {
                $compareProperties.Add([PSCustomObject]@{
                        PropertyName = $propName
                        Object1Value = $value1
                        Object2Value = $value2
                        Match        = $match
                    })
            }
        }

        # Compare all other properties
        $addedProps = [System.Collections.Generic.List[string]]::new()
        foreach ($propName in ($obj1.PSObject.Properties | Select-Object Name).Name) {
            if ($propName -in $coreProps) { continue }
            if ($propName -in $postProps) { continue }
            if ($propName -in $skipProps) { continue }

            if ($propName -like '*@OData*' -or $propName -like '#microsoft.graph*') { continue }

            $addedProps.Add($propName)
            $val1 = ($obj1.$propName | ConvertTo-Json -Depth 10)
            $val2 = ($obj2.$propName | ConvertTo-Json -Depth 10)

            $value1 = if ($null -eq $val1) { '' } else { $val1.ToString().Trim('"') }
            $value2 = if ($null -eq $val2) { '' } else { $val2.ToString().Trim('"') }

            $match = ($value1 -eq $value2)

            if (-not $match) {
                $compareProperties.Add([PSCustomObject]@{
                        PropertyName = $propName
                        Object1Value = $value1
                        Object2Value = $value2
                        Match        = $match
                    })
            }
        }

        # Check for properties in obj2 that aren't in obj1
        foreach ($propName in ($obj2.PSObject.Properties | Select-Object Name).Name) {
            if ($propName -in $coreProps) { continue }
            if ($propName -in $postProps) { continue }
            if ($propName -in $skipProps) { continue }
            if ($propName -in $addedProps) { continue }

            if ($propName -like '*@OData*' -or $propName -like '#microsoft.graph*') { continue }

            $val1 = ($obj1.$propName | ConvertTo-Json -Depth 10)
            $val2 = ($obj2.$propName | ConvertTo-Json -Depth 10)

            $value1 = if ($null -eq $val1) { '' } else { $val1.ToString().Trim('"') }
            $value2 = if ($null -eq $val2) { '' } else { $val2.ToString().Trim('"') }

            $match = ($value1 -eq $value2)

            if (-not $match) {
                $compareProperties.Add([PSCustomObject]@{
                        PropertyName = $propName
                        Object1Value = $value1
                        Object2Value = $value2
                        Match        = $match
                    })
            }
        }

        # Compare post properties (like Advertisements)
        foreach ($propName in $postProps) {
            if (-not ($obj1.PSObject.Properties | Where-Object Name -EQ $propName)) {
                continue
            }
            $val1 = ($obj1.$propName | ConvertTo-Json -Depth 10)
            $val2 = ($obj2.$propName | ConvertTo-Json -Depth 10)

            $value1 = if ($null -eq $val1) { '' } else { $val1.ToString().Trim('"') }
            $value2 = if ($null -eq $val2) { '' } else { $val2.ToString().Trim('"') }

            $match = ($value1 -eq $value2)

            if (-not $match) {
                $compareProperties.Add([PSCustomObject]@{
                        PropertyName = $propName
                        Object1Value = $value1
                        Object2Value = $value2
                        Match        = $match
                    })
            }
        }

        # If no differences found, return null
        if ($compareProperties.Count -eq 0) {
            return $null
        }

        # Convert to a more user-friendly format
        $result = [System.Collections.Generic.List[PSObject]]::new()
        foreach ($diff in $compareProperties) {
            $result.Add([PSCustomObject]@{
                    Property      = $diff.PropertyName
                    ExpectedValue = $diff.Object1Value
                    ReceivedValue = $diff.Object2Value
                })
        }
    } else {
        $intuneCollection = Get-Content .\intuneCollection.json | ConvertFrom-Json -ErrorAction SilentlyContinue

        # Process reference object settings
        $referenceItems = $ReferenceObject.settings | ForEach-Object {
            $settingInstance = $_.settingInstance
            $intuneObj = $intuneCollection | Where-Object { $_.id -eq $settingInstance.settingDefinitionId }
            $tempOutput = switch ($settingInstance.'@odata.type') {
                '#microsoft.graph.deviceManagementConfigurationGroupSettingCollectionInstance' {
                    if ($null -ne $settingInstance.groupSettingCollectionValue) {
                        foreach ($groupValue in $settingInstance.groupSettingCollectionValue) {
                            if ($groupValue.children -is [System.Array]) {
                                foreach ($child in $groupValue.children) {
                                    $childIntuneObj = $intuneCollection | Where-Object { $_.id -eq $child.settingDefinitionId }
                                    $childLabel = if ($childIntuneObj?.displayName) {
                                        $childIntuneObj.displayName
                                    } else {
                                        $child.settingDefinitionId
                                    }
                                    $childValue = $null
                                    if ($child.choiceSettingValue?.value) {
                                        $option = $childIntuneObj.options | Where-Object {
                                            $_.id -eq $child.choiceSettingValue.value
                                        }
                                        $childValue = if ($option?.displayName) {
                                            $option.displayName
                                        } else {
                                            $child.choiceSettingValue.value
                                        }
                                    }

                                    # Add object to our temporary list
                                    [PSCustomObject]@{
                                        Key    = "GroupChild-$($child.settingDefinitionId)"
                                        Label  = $childLabel
                                        Value  = $childValue
                                        Source = 'Reference'
                                    }
                                }
                            }
                        }
                    }
                }
                Default {
                    if ($settingInstance.simpleSettingValue?.value) {
                        $label = if ($intuneObj?.displayName) {
                            $intuneObj.displayName
                        } else {
                            $settingInstance.settingDefinitionId
                        }
                        $value = $settingInstance.simpleSettingValue.value
                        [PSCustomObject]@{
                            Key    = "Simple-$($settingInstance.settingDefinitionId)"
                            Label  = $label
                            Value  = $value
                            Source = 'Reference'
                        }
                    } elseif ($settingInstance.choiceSettingValue?.value) {
                        $label = if ($intuneObj?.displayName) {
                            $intuneObj.displayName
                        } else {
                            $settingInstance.settingDefinitionId
                        }

                        $option = $intuneObj.options | Where-Object {
                            $_.id -eq $settingInstance.choiceSettingValue.value
                        }
                        $value = if ($option?.displayName) {
                            $option.displayName
                        } else {
                            $settingInstance.choiceSettingValue.value
                        }

                        [PSCustomObject]@{
                            Key    = "Choice-$($settingInstance.settingDefinitionId)"
                            Label  = $label
                            Value  = $value
                            Source = 'Reference'
                        }
                    } else {
                        $label = if ($intuneObj?.displayName) {
                            $intuneObj.displayName
                        } else {
                            $settingInstance.settingDefinitionId
                        }
                        [PSCustomObject]@{
                            Key    = "Unknown-$($settingInstance.settingDefinitionId)"
                            Label  = $label
                            Value  = 'This setting could not be resolved'
                            Source = 'Reference'
                        }
                    }
                }
            }
            $tempOutput
        }

        # Process difference object settings
        $differenceItems = $DifferenceObject.settings | ForEach-Object {
            $settingInstance = $_.settingInstance
            $intuneObj = $intuneCollection | Where-Object { $_.id -eq $settingInstance.settingDefinitionId }
            $tempOutput = switch ($settingInstance.'@odata.type') {
                '#microsoft.graph.deviceManagementConfigurationGroupSettingCollectionInstance' {
                    if ($null -ne $settingInstance.groupSettingCollectionValue) {
                        foreach ($groupValue in $settingInstance.groupSettingCollectionValue) {
                            if ($groupValue.children -is [System.Array]) {
                                foreach ($child in $groupValue.children) {
                                    $childIntuneObj = $intuneCollection | Where-Object { $_.id -eq $child.settingDefinitionId }
                                    $childLabel = if ($childIntuneObj?.displayName) {
                                        $childIntuneObj.displayName
                                    } else {
                                        $child.settingDefinitionId
                                    }
                                    $childValue = $null
                                    if ($child.choiceSettingValue?.value) {
                                        $option = $childIntuneObj.options | Where-Object {
                                            $_.id -eq $child.choiceSettingValue.value
                                        }
                                        $childValue = if ($option?.displayName) {
                                            $option.displayName
                                        } else {
                                            $child.choiceSettingValue.value
                                        }
                                    }

                                    # Add object to our temporary list
                                    [PSCustomObject]@{
                                        Key    = "GroupChild-$($child.settingDefinitionId)"
                                        Label  = $childLabel
                                        Value  = $childValue
                                        Source = 'Difference'
                                    }
                                }
                            }
                        }
                    }
                }
                Default {
                    if ($settingInstance.simpleSettingValue?.value) {
                        $label = if ($intuneObj?.displayName) {
                            $intuneObj.displayName
                        } else {
                            $settingInstance.settingDefinitionId
                        }
                        $value = $settingInstance.simpleSettingValue.value
                        [PSCustomObject]@{
                            Key    = "Simple-$($settingInstance.settingDefinitionId)"
                            Label  = $label
                            Value  = $value
                            Source = 'Difference'
                        }
                    } elseif ($settingInstance.choiceSettingValue?.value) {
                        $label = if ($intuneObj?.displayName) {
                            $intuneObj.displayName
                        } else {
                            $settingInstance.settingDefinitionId
                        }

                        $option = $intuneObj.options | Where-Object {
                            $_.id -eq $settingInstance.choiceSettingValue.value
                        }
                        $value = if ($option?.displayName) {
                            $option.displayName
                        } else {
                            $settingInstance.choiceSettingValue.value
                        }

                        [PSCustomObject]@{
                            Key    = "Choice-$($settingInstance.settingDefinitionId)"
                            Label  = $label
                            Value  = $value
                            Source = 'Difference'
                        }
                    } else {
                        $label = if ($intuneObj?.displayName) {
                            $intuneObj.displayName
                        } else {
                            $settingInstance.settingDefinitionId
                        }
                        [PSCustomObject]@{
                            Key    = "Unknown-$($settingInstance.settingDefinitionId)"
                            Label  = $label
                            Value  = 'This setting could not be resolved'
                            Source = 'Difference'
                        }
                    }
                }
            }
            $tempOutput
        }

        # Compare the items and create result
        $result = [System.Collections.Generic.List[PSObject]]::new()

        # Group all items by Key for comparison
        $allKeys = @($referenceItems | Select-Object -ExpandProperty Key) + @($differenceItems | Select-Object -ExpandProperty Key) | Sort-Object -Unique

        foreach ($key in $allKeys) {
            $refItem = $referenceItems | Where-Object { $_.Key -eq $key } | Select-Object -First 1
            $diffItem = $differenceItems | Where-Object { $_.Key -eq $key } | Select-Object -First 1

            # Get the setting definition ID from the key
            $settingId = $key
            if ($key -like 'Simple-*') {
                $settingId = $key.Substring(7)
            } elseif ($key -like 'Choice-*') {
                $settingId = $key.Substring(7)
            } elseif ($key -like 'GroupChild-*') {
                $settingId = $key.Substring(11)
            } elseif ($key -like 'Unknown-*') {
                $settingId = $key.Substring(8)
            }

            # Look up the setting in the collection
            $settingDefinition = $intuneCollection | Where-Object { $_.id -eq $settingId }

            # Get the raw values
            $refRawValue = if ($refItem) { $refItem.Value } else { $null }
            $diffRawValue = if ($diffItem) { $diffItem.Value } else { $null }

            # Try to translate the values to display names if they're option IDs
            $refValue = $refRawValue
            $diffValue = $diffRawValue

            # If the setting has options, try to find the display name for the values
            if ($null -ne $settingDefinition -and $null -ne $settingDefinition.options) {
                # For reference value
                if ($null -ne $refRawValue -and $refRawValue -match '_\d+$') {
                    $option = $settingDefinition.options | Where-Object { $_.id -eq $refRawValue }
                    if ($null -ne $option -and $null -ne $option.displayName) {
                        $refValue = $option.displayName
                    }
                }

                # For difference value
                if ($null -ne $diffRawValue -and $diffRawValue -match '_\d+$') {
                    $option = $settingDefinition.options | Where-Object { $_.id -eq $diffRawValue }
                    if ($null -ne $option -and $null -ne $option.displayName) {
                        $diffValue = $option.displayName
                    }
                }
            }

            # Use the display name for the property label if available
            $label = if ($null -ne $settingDefinition -and $null -ne $settingDefinition.displayName) {
                $settingDefinition.displayName
            } elseif ($refItem) {
                $refItem.Label
            } elseif ($diffItem) {
                $diffItem.Label
            } else {
                $key
            }

            # Only add to result if values are different or one is missing
            if ($refRawValue -ne $diffRawValue -or $null -eq $refRawValue -or $null -eq $diffRawValue) {
                $result.Add([PSCustomObject]@{
                        Property      = $label
                        ExpectedValue = $refValue
                        ReceivedValue = $diffValue
                    })
            }
        }

        return $result
    }
    return $result
}

