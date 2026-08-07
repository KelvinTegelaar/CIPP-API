function Remove-CIPPReusableSettingMetadata {
    param($InputObject)

    $metadataFields = @(
        'id',
        'createdDateTime',
        'lastModifiedDateTime',
        'version',
        '@odata.context',
        '@odata.etag',
        'referencingConfigurationPolicyCount',
        'settingInstanceTemplateReference',
        'settingValueTemplateReference',
        'auditRuleInformation'
    )

    function ConvertTo-NormalizedObject {
        param($Value)

        if ($null -eq $Value) { return $null }

        function Test-IsCollection {
            param($Candidate)
            return (
                $Candidate -is [System.Collections.IEnumerable] -and
                $Candidate -isnot [string] -and
                (
                    $Candidate -is [System.Array] -or
                    $Candidate -is [System.Collections.IList] -or
                    $Candidate -is [System.Collections.ICollection]
                )
            )
        }

        function ConvertTo-NormalizedEntry {
            param($Entries)

            $output = [ordered]@{}
            foreach ($entry in $Entries) {
                $name = $entry.Name
                $item = $entry.Value

                if ($name -ieq 'children') {
                    if ($null -eq $item) {
                        $output[$name] = @()
                    } elseif (Test-IsCollection -Candidate $item) {
                        $output[$name] = ConvertTo-NormalizedObject -Value $item
                    } else {
                        $output[$name] = @(ConvertTo-NormalizedObject -Value $item)
                    }
                    continue
                }

                if ($name -ieq 'groupSettingCollectionValue') {
                    if ($null -eq $item) {
                        $output[$name] = @()
                        continue
                    }

                    if (Test-IsCollection -Candidate $item) {
                        $output[$name] = ConvertTo-NormalizedObject -Value $item
                    } else {
                        $output[$name] = @(ConvertTo-NormalizedObject -Value $item)
                    }
                    continue
                }

                if ($null -eq $item) { continue }
                if ($name -in $metadataFields) { continue }
                $output[$name] = ConvertTo-NormalizedObject -Value $item
            }

            if ($output.Contains('children') -and -not (Test-IsCollection -Candidate $output['children'])) {
                $output['children'] = @($output['children'])
            }

            if (
                $output.Contains('groupSettingCollectionValue') -and
                -not (Test-IsCollection -Candidate $output['groupSettingCollectionValue'])
            ) {
                $output['groupSettingCollectionValue'] = @($output['groupSettingCollectionValue'])
            }

            return [pscustomobject]$output
        }

        if ($Value -is [System.Collections.IDictionary]) {
            $entries = foreach ($key in $Value.Keys) {
                [pscustomobject]@{ Name = $key; Value = $Value[$key] }
            }
            return ConvertTo-NormalizedEntry -Entries $entries
        }

        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
            $cleanArray = [System.Collections.Generic.List[object]]::new()
            foreach ($entry in $Value) {
                $cleanArray.Add((ConvertTo-NormalizedObject -Value $entry))
            }
            return $cleanArray
        }

        if ($Value -is [psobject]) {
            $entries = foreach ($prop in $Value.PSObject.Properties) {
                [pscustomobject]@{ Name = $prop.Name; Value = $prop.Value }
            }
            return ConvertTo-NormalizedEntry -Entries $entries
        }

        return $Value
    }

    return ConvertTo-NormalizedObject -Value $InputObject
}
