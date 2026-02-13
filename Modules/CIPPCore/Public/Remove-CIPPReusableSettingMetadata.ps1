function Remove-CIPPReusableSettingMetadata {
    param($InputObject)

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $cleanArray = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $InputObject) { $cleanArray.Add((Remove-CIPPReusableSettingMetadata -InputObject $item)) }
        return $cleanArray
    }

    if ($InputObject -is [psobject]) {
        $output = [ordered]@{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            if ($null -eq $prop.Value) { continue }
            if ($prop.Name -in @('id','createdDateTime','lastModifiedDateTime','version','@odata.context','@odata.etag','referencingConfigurationPolicyCount','settingInstanceTemplateReference','settingValueTemplateReference','auditRuleInformation')) { continue }
            $output[$prop.Name] = Remove-CIPPReusableSettingMetadata -InputObject $prop.Value
        }
        return [pscustomobject]$output
    }

    return $InputObject
}
