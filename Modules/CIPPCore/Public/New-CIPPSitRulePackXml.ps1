function New-CIPPSitRulePackXml {
    <#
    .SYNOPSIS
        Synthesize a Microsoft Purview Sensitive Information Type rule pack XML from simple inputs.
    .DESCRIPTION
        New-DlpSensitiveInformationType only accepts a rule pack XML via -FileData (byte array).
        For simple regex-based SITs, this helper builds a minimal valid rule pack with fresh GUIDs
        so callers can pass it to the cmdlet without hand-authoring XML.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
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
