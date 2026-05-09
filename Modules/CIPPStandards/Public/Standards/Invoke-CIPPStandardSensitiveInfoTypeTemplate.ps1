function Invoke-CIPPStandardSensitiveInfoTypeTemplate {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SensitiveInfoTypeTemplate
    .SYNOPSIS
        (Label) Sensitive Information Type Template
    .DESCRIPTION
        (Helptext) Deploy custom Microsoft Purview Sensitive Information Types from CIPP templates. Existing custom SITs with the same name are overwritten in place.
        (DocsDescription) Deploy custom Sensitive Information Types from CIPP templates. Supports the simple-mode template (Name + Pattern + Confidence — backend synthesizes the rule pack XML) and the advanced-mode template (caller-supplied FileDataBase64 rule pack). If a SIT with the same name already exists, its rule pack is updated in place via Set-DlpSensitiveInformationType. Built-in Microsoft SITs cannot be modified and will be skipped.
    .NOTES
        MULTI
            True
        CAT
            Templates
        DISABLEDFEATURES
            {"report":false,"warn":true,"remediate":false}
        IMPACT
            Low Impact
        ADDEDDATE
            2026-05-10
        EXECUTIVETEXT
            Deploys custom Sensitive Information Types so DLP policies can detect organization-specific identifiers — employee IDs, project codenames, internal account numbers — across tenants consistently.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":true,"creatable":false,"name":"sensitiveInfoTypeTemplate","label":"Select Sensitive Information Type Templates","api":{"url":"/api/ListSensitiveInfoTypeTemplates","labelField":"name","valueField":"GUID","queryKey":"ListSensitiveInfoTypeTemplates"}}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)

    function New-CippSitRulePackXml {
        param(
            [Parameter(Mandatory)][string]$Name,
            [string]$Description,
            [Parameter(Mandatory)][string]$Pattern,
            [int]$Confidence = 85,
            [int]$PatternsProximity = 300,
            [string]$Locale = 'en-us',
            [string]$PublisherName = 'CIPP'
        )

        $RulePackId = (New-Guid).Guid
        $PublisherId = (New-Guid).Guid
        $EntityId = (New-Guid).Guid
        $RegexId = "Regex_$(((New-Guid).Guid) -replace '-')"
        $esc = { param($s) [System.Security.SecurityElement]::Escape([string]$s) }

        return @"
<?xml version="1.0" encoding="UTF-8"?>
<RulePackage xmlns="http://schemas.microsoft.com/office/2018/09/search.external/rulepack">
  <RulePack id="$RulePackId">
    <Version major="1" minor="0" patch="0" build="0"/>
    <Publisher id="$PublisherId"/>
    <Details defaultLangCode="$Locale">
      <LocalizedDetails langcode="$Locale">
        <PublisherName>$(& $esc $PublisherName)</PublisherName>
        <Name>$(& $esc $Name)</Name>
        <Description>$(& $esc $Description)</Description>
      </LocalizedDetails>
    </Details>
  </RulePack>
  <Rules>
    <Entity id="$EntityId" patternsProximity="$PatternsProximity" recommendedConfidence="$Confidence">
      <Pattern confidenceLevel="$Confidence">
        <IdMatch idRef="$RegexId"/>
      </Pattern>
    </Entity>
    <Regex id="$RegexId">$(& $esc $Pattern)</Regex>
    <LocalizedStrings>
      <Resource idRef="$EntityId">
        <Name default="true" langcode="$Locale">$(& $esc $Name)</Name>
        <Description default="true" langcode="$Locale">$(& $esc $Description)</Description>
      </Resource>
    </LocalizedStrings>
  </Rules>
</RulePackage>
"@
    }

    $TemplateSelection = $Settings.sensitiveInfoTypeTemplate ?? $Settings.TemplateList ?? $Settings.'standards.SensitiveInfoTypeTemplate.TemplateIds'
    $TemplateIds = @($TemplateSelection | ForEach-Object {
            if ($_ -is [string]) { $_ } elseif ($_.value) { $_.value } else { $null }
        }) | Where-Object { $_ }

    if (-not $TemplateIds -or $TemplateIds.Count -eq 0) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No sensitive information type templates selected.' -sev Error
        return
    }

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'SensitiveInfoTypeTemplate' and (RowKey eq '$($TemplateIds -join "' or RowKey eq '")')"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json

    if (-not $Templates) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No sensitive information type templates resolved from the selected IDs.' -sev Error
        return
    }

    try {
        $ExistingSits = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-DlpSensitiveInformationType' -Compliance | Select-Object Name, Publisher
    } catch {
        $ExistingSits = @()
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not list existing sensitive information types: $($_.Exception.Message)" -sev Warning
    }

    if ($Settings.remediate -eq $true) {
        foreach ($Template in @($Templates)) {
            $TemplateName = $Template.Name ?? $Template.name
            try {
                # Build the rule pack bytes (simple mode synthesizes XML, advanced mode decodes base64)
                $FileDataBytes = $null
                if ($Template.FileDataBase64) {
                    $FileDataBytes = [System.Convert]::FromBase64String($Template.FileDataBase64)
                } elseif ($Template.Pattern) {
                    $Xml = New-CippSitRulePackXml `
                        -Name $TemplateName `
                        -Description ($Template.Description ?? '') `
                        -Pattern $Template.Pattern `
                        -Confidence ([int]($Template.Confidence ?? 85)) `
                        -PatternsProximity ([int]($Template.PatternsProximity ?? 300)) `
                        -Locale ($Template.Locale ?? 'en-us') `
                        -PublisherName ($Template.PublisherName ?? 'CIPP')
                    $FileDataBytes = [System.Text.Encoding]::UTF8.GetBytes($Xml)
                } else {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Sensitive Information Type template '$TemplateName' is missing both 'Pattern' and 'FileDataBase64' — skipping." -sev Error
                    continue
                }

                $Existing = $ExistingSits | Where-Object { $_.Name -eq $TemplateName } | Select-Object -First 1

                if ($Existing) {
                    # Block updates to Microsoft built-ins — they're locked at the platform level
                    if ($Existing.Publisher -like 'Microsoft*') {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Sensitive Information Type '$TemplateName' is a built-in Microsoft type and cannot be overwritten — skipping." -sev Warning
                        continue
                    }

                    $SetParams = @{
                        Identity = $TemplateName
                        FileData = $FileDataBytes
                    }
                    if (-not [string]::IsNullOrWhiteSpace([string]$Template.Description)) {
                        $SetParams['Description'] = $Template.Description
                    }
                    if (-not [string]::IsNullOrWhiteSpace([string]$Template.Locale)) {
                        $SetParams['Locale'] = $Template.Locale
                    }

                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-DlpSensitiveInformationType' -cmdParams $SetParams -Compliance -useSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated Sensitive Information Type '$TemplateName' in place" -sev Info
                } else {
                    $NewParams = @{
                        Name     = $TemplateName
                        FileData = $FileDataBytes
                    }
                    if (-not [string]::IsNullOrWhiteSpace([string]$Template.Description)) {
                        $NewParams['Description'] = $Template.Description
                    }
                    if (-not [string]::IsNullOrWhiteSpace([string]$Template.Locale)) {
                        $NewParams['Locale'] = $Template.Locale
                    }

                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'New-DlpSensitiveInformationType' -cmdParams $NewParams -Compliance -useSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created Sensitive Information Type '$TemplateName'" -sev Info
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to deploy Sensitive Information Type '$TemplateName'. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.report -eq $true) {
        $MissingSits = foreach ($Template in @($Templates)) {
            $TemplateName = $Template.Name ?? $Template.name
            if (-not ($ExistingSits | Where-Object { $_.Name -eq $TemplateName })) { $TemplateName }
        }

        $CurrentValue = @{ MissingSensitiveInfoTypes = $MissingSits ? @($MissingSits) : @() }
        $ExpectedValue = @{ MissingSensitiveInfoTypes = @() }

        Set-CIPPStandardsCompareField -FieldName 'standards.SensitiveInfoTypeTemplate' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
    }
}
