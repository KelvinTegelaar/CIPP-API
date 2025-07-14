function Compare-CIPPIntuneObject {
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

        $excludeProps = $defaultExcludeProperties + $ExcludeProperties
        $result = [System.Collections.Generic.List[PSObject]]::new()

        function ShouldSkipProperty {
            param (
                [string]$PropertyName
            )
            return ($PropertyName -like '*@OData*' -or
                $PropertyName -like '#microsoft.graph*' -or
                $excludeProps -contains $PropertyName)
        }

        function Compare-ObjectsRecursively {
            param (
                [Parameter(Mandatory = $true)]
                $Object1,

                [Parameter(Mandatory = $true)]
                $Object2,

                [Parameter(Mandatory = $false)]
                [string]$PropertyPath = '',
                [int]$Depth = 0,
                [int]$MaxDepth = 20
            )

            if ($Depth -ge $MaxDepth) {
                $result.Add([PSCustomObject]@{
                        Property      = $PropertyPath
                        ExpectedValue = '[MaxDepthExceeded]'
                        ReceivedValue = '[MaxDepthExceeded]'
                    })
                return
            }

            if (($null -eq $Object1 -or $Object1 -eq '') -and ($null -eq $Object2 -or $Object2 -eq '')) {
                return
            }

            if (($null -eq $Object1 -or $Object1 -eq '') -xor ($null -eq $Object2 -or $Object2 -eq '')) {
                $result.Add([PSCustomObject]@{
                        Property      = $PropertyPath
                        ExpectedValue = if ($null -eq $Object1) { '' } else { $Object1 }
                        ReceivedValue = if ($null -eq $Object2) { '' } else { $Object2 }
                    })
                return
            }

            if ($Object1.GetType() -ne $Object2.GetType()) {
                $result.Add([PSCustomObject]@{
                        Property      = $PropertyPath
                        ExpectedValue = $Object1
                        ReceivedValue = $Object2
                    })
                return
            }

            # Short-circuit recursion for primitive types
            $primitiveTypes = @([double], [decimal], [datetime], [timespan], [guid] )
            foreach ($type in $primitiveTypes) {
                if ($Object1 -is $type -and $Object2 -is $type) {
                    if ($Object1 -ne $Object2) {
                        $result.Add([PSCustomObject]@{
                                Property      = $PropertyPath
                                ExpectedValue = $Object1
                                ReceivedValue = $Object2
                            })
                    }
                    return
                }
            }

            if ($Object1 -is [System.Collections.IDictionary]) {
                $allKeys = @($Object1.Keys) + @($Object2.Keys) | Select-Object -Unique

                foreach ($key in $allKeys) {
                    if (ShouldSkipProperty -PropertyName $key) { continue }

                    $newPath = if ($PropertyPath) { "$PropertyPath.$key" } else { $key }

                    if ($Object1.ContainsKey($key) -and $Object2.ContainsKey($key)) {
                        if ($Object1[$key] -and $Object2[$key]) {
                            Compare-ObjectsRecursively -Object1 $Object1[$key] -Object2 $Object2[$key] -PropertyPath $newPath -Depth ($Depth + 1) -MaxDepth $MaxDepth
                        }
                    } elseif ($Object1.ContainsKey($key)) {
                        $result.Add([PSCustomObject]@{
                                Property      = $newPath
                                ExpectedValue = $Object1[$key]
                                ReceivedValue = ''
                            })
                    } else {
                        $result.Add([PSCustomObject]@{
                                Property      = $newPath
                                ExpectedValue = ''
                                ReceivedValue = $Object2[$key]
                            })
                    }
                }
            } elseif ($Object1 -is [Array] -or $Object1 -is [System.Collections.IList]) {
                $maxLength = [Math]::Max($Object1.Count, $Object2.Count)

                for ($i = 0; $i -lt $maxLength; $i++) {
                    $newPath = "$PropertyPath.$i"

                    if ($i -lt $Object1.Count -and $i -lt $Object2.Count) {
                        Compare-ObjectsRecursively -Object1 $Object1[$i] -Object2 $Object2[$i] -PropertyPath $newPath -Depth ($Depth + 1) -MaxDepth $MaxDepth
                    } elseif ($i -lt $Object1.Count) {
                        $result.Add([PSCustomObject]@{
                                Property      = $newPath
                                ExpectedValue = $Object1[$i]
                                ReceivedValue = ''
                            })
                    } else {
                        $result.Add([PSCustomObject]@{
                                Property      = $newPath
                                ExpectedValue = ''
                                ReceivedValue = $Object2[$i]
                            })
                    }
                }
            } elseif ($Object1 -is [PSCustomObject] -or $Object1.PSObject.Properties.Count -gt 0) {
                $allPropertyNames = @(
                    $Object1.PSObject.Properties | Select-Object -ExpandProperty Name
                    $Object2.PSObject.Properties | Select-Object -ExpandProperty Name
                ) | Select-Object -Unique

                foreach ($propName in $allPropertyNames) {
                    if (ShouldSkipProperty -PropertyName $propName) { continue }

                    $newPath = if ($PropertyPath) { "$PropertyPath.$propName" } else { $propName }
                    $prop1Exists = $Object1.PSObject.Properties.Name -contains $propName
                    $prop2Exists = $Object2.PSObject.Properties.Name -contains $propName

                    if ($prop1Exists -and $prop2Exists) {
                        if ($Object1.$propName -and $Object2.$propName) {
                            Compare-ObjectsRecursively -Object1 $Object1.$propName -Object2 $Object2.$propName -PropertyPath $newPath -Depth ($Depth + 1) -MaxDepth $MaxDepth
                        }
                    } elseif ($prop1Exists) {
                        $result.Add([PSCustomObject]@{
                                Property      = $newPath
                                ExpectedValue = $Object1.$propName
                                ReceivedValue = ''
                            })
                    } else {
                        $result.Add([PSCustomObject]@{
                                Property      = $newPath
                                ExpectedValue = ''
                                ReceivedValue = $Object2.$propName
                            })
                    }
                }
            } else {
                $val1 = $Object1.ToString()
                $val2 = $Object2.ToString()

                if ($val1 -ne $val2) {
                    $result.Add([PSCustomObject]@{
                            Property      = $PropertyPath
                            ExpectedValue = $val1
                            ReceivedValue = $val2
                        })
                }
            }
        }

        $obj1 = if ($ReferenceObject -is [string]) {
            $ReferenceObject | ConvertFrom-Json -AsHashtable -Depth 100
        } else {
            $ReferenceObject
        }

        $obj2 = if ($DifferenceObject -is [string]) {
            $DifferenceObject | ConvertFrom-Json -AsHashtable -Depth 100
        } else {
            $DifferenceObject
        }

        if ($obj1 -and $obj2) {
            Compare-ObjectsRecursively -Object1 $obj1 -Object2 $obj2
        }

        if ($result.Count -eq 0) {
            return $null
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
                default {
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
                                        if (!$childValue -and $child.simpleSettingValue.value) {
                                            $childValue = $child.simpleSettingValue.value
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
                default {
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

        $result = [System.Collections.Generic.List[PSObject]]::new()

        $allKeys = @($referenceItems | Select-Object -ExpandProperty Key) + @($differenceItems | Select-Object -ExpandProperty Key) | Sort-Object -Unique

        foreach ($key in $allKeys) {
            $refItem = $referenceItems | Where-Object { $_.Key -eq $key } | Select-Object -First 1
            $diffItem = $differenceItems | Where-Object { $_.Key -eq $key } | Select-Object -First 1

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

            $settingDefinition = $intuneCollection | Where-Object { $_.id -eq $settingId }

            $refRawValue = if ($refItem) { $refItem.Value } else { $null }
            $diffRawValue = if ($diffItem) { $diffItem.Value } else { $null }

            $refValue = $refRawValue
            $diffValue = $diffRawValue

            if ($null -ne $settingDefinition -and $null -ne $settingDefinition.options) {
                if ($null -ne $refRawValue -and $refRawValue -match '_\d+$') {
                    $option = $settingDefinition.options | Where-Object { $_.id -eq $refRawValue }
                    if ($null -ne $option -and $null -ne $option.displayName) {
                        $refValue = $option.displayName
                    }
                }

                if ($null -ne $diffRawValue -and $diffRawValue -match '_\d+$') {
                    $option = $settingDefinition.options | Where-Object { $_.id -eq $diffRawValue }
                    if ($null -ne $option -and $null -ne $option.displayName) {
                        $diffValue = $option.displayName
                    }
                }
            }

            $label = if ($null -ne $settingDefinition -and $null -ne $settingDefinition.displayName) {
                $settingDefinition.displayName
            } elseif ($refItem) {
                $refItem.Label
            } elseif ($diffItem) {
                $diffItem.Label
            } else {
                $key
            }

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
