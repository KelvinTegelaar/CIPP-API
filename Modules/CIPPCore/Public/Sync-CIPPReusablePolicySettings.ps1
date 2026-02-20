function Sync-CIPPReusablePolicySettings {
    param(
        [psobject]$TemplateInfo,
        [string]$Tenant
    )

    $result = [pscustomobject]@{
        RawJSON = $TemplateInfo.RawJSON
        Map     = @{}
    }

    $reusableRefs = @($TemplateInfo.ReusableSettings)
    if (-not $reusableRefs) { return $result }

    $existingReusableSettings = New-GraphGETRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/reusablePolicySettings?$top=999' -tenantid $Tenant
    $table = Get-CippTable -tablename 'templates'
    $templateEntities = Get-CIPPAzDataTableEntity @table -Filter "PartitionKey eq 'IntuneReusableSettingTemplate'"

    foreach ($ref in $reusableRefs) {
        $templateId = $ref.templateId ?? $ref.templateID ?? $ref.GUID ?? $ref.RowKey
        $sourceId = $ref.sourceId ?? $ref.sourceReusableSettingId ?? $ref.sourceGuid ?? $ref.id
        $displayName = $ref.displayName ?? $ref.DisplayName

        if (-not $templateId -or -not $displayName) { continue }

        $templateEntity = $templateEntities | Where-Object { $_.RowKey -eq $templateId } | Select-Object -First 1
        if (-not $templateEntity) { continue }

        $templateData = $templateEntity.JSON | ConvertFrom-Json -Depth 200 -ErrorAction SilentlyContinue
        $templateRaw = $templateData.RawJSON
        if ($templateRaw -is [string] -and $templateRaw -match '"children"\s*:\s*null') {
            try {
                $templateRaw = [regex]::Replace($templateRaw, '"children"\s*:\s*null', '"children":[]', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            } catch {}
        }
        $templateBody = $templateRaw | ConvertFrom-Json -Depth 200 -ErrorAction SilentlyContinue
        if (-not $templateRaw -or -not $templateBody) { continue }
        $existingMatch = $existingReusableSettings | Where-Object -Property displayName -EQ $displayName | Select-Object -First 1
        $targetId = $existingMatch.id
        $needsUpdate = $false

        if ($existingMatch) {
            try {
                $existingClean = $existingMatch | Select-Object -Property * -ExcludeProperty id, createdDateTime, lastModifiedDateTime, version, '@odata.context', '@odata.etag'
                $compare = Compare-CIPPIntuneObject -ReferenceObject $templateBody -DifferenceObject $existingClean -compareType 'ReusablePolicySetting' -ErrorAction SilentlyContinue
                if ($compare) { $needsUpdate = $true }
            } catch {
                $needsUpdate = $true
            }
        } else {
            $needsUpdate = $true
        }

        if ($needsUpdate) {
            try {
                if ($targetId) {
                    $updated = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/reusablePolicySettings/$targetId" -tenantid $Tenant -type PUT -body $templateRaw
                    $targetId = $updated.id ?? $targetId
                } else {
                    $created = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/reusablePolicySettings' -tenantid $Tenant -type POST -body $templateRaw
                    $targetId = $created.id ?? $targetId
                }
            } catch {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to deploy reusable setting $($displayName): $($_.Exception.Message)" -sev 'Error'
            }
        }

        if ($sourceId -and $targetId) { $result.Map[$sourceId] = $targetId }
    }

    $updatedJson = $result.RawJSON
    foreach ($pair in $result.Map.GetEnumerator()) {
        $updatedJson = $updatedJson -replace [regex]::Escape($pair.Key), $pair.Value
    }
    $result.RawJSON = $updatedJson

    return $result
}
