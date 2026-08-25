function Get-CIPPBaselineDeployContactTemplatesState {
    <#
    .SYNOPSIS
        Prepare hook for DeployContactTemplates: is this instance's mail contact deployed
        and in sync.
    .DESCRIPTION
        One instance grades ONE contact - a contact template IS one contact. Matched on
        DisplayName, then diffed field-by-field with the classic's exact rules:

        - email compares case-insensitively against ExternalEmailAddress (the cache already
          strips the SMTP: prefix and lowercases, so the template side is lowered here too)
        - hidefromGAL is a BOOLEAN and is enforced in both directions
        - every other field is enforced only when the template specifies a value; an empty
          template field expresses no opinion, and grading it would strip operator data

        The ExoMailContacts cache merges Get-Contact's extended properties (Company, City,
        Phone...) flat onto each row, so no per-contact live read is needed.

        A template with no displayName, no email, or an invalid email address cannot be
        evaluated or deployed - the classic skipped it silently; here it reports No Data.

        Template resolution stays per-family: PartitionKey 'ContactTemplate' - one of the
        three partitions that do NOT match their standard name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Contacts = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoMailContacts')
    if ($Contacts.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ExoMailContacts')) {
        return @{ Current = $null }
    }

    $Reference = $Item.Variables.contactTemplate
    if ($Reference -is [System.Management.Automation.PSCustomObject] -and $Reference.PSObject.Properties.Name -contains 'value') { $Reference = $Reference.value }
    if ([string]::IsNullOrWhiteSpace("$Reference")) { return @{ Current = $null } }

    $Table = Get-CippTable -tablename 'templates'
    $SafeReference = ConvertTo-CIPPODataFilterValue -Value "$Reference"
    $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'ContactTemplate' and RowKey eq '$SafeReference'" | Select-Object -First 1
    $Template = $(if ($Entity -and -not [string]::IsNullOrWhiteSpace($Entity.JSON)) { try { $Entity.JSON | ConvertFrom-Json -Depth 20 -ErrorAction Stop } catch { $null } })
    if (-not $Template) { return @{ Current = $null } }

    $ContactName = "$($Template.displayName)"
    $Email = "$($Template.email)"
    if ([string]::IsNullOrWhiteSpace($ContactName) -or [string]::IsNullOrWhiteSpace($Email)) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Contact template '$Reference' is missing a display name or email address and cannot be evaluated." -Sev 'Error'
        return @{ Current = $null }
    }
    try { $null = [System.Net.Mail.MailAddress]::new($Email) } catch {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Contact template '$ContactName' has an invalid email address '$Email' and cannot be evaluated." -Sev 'Error'
        return @{ Current = $null }
    }

    $Existing = $Contacts | Where-Object { "$($_.DisplayName)" -eq $ContactName } | Select-Object -First 1

    if (-not $Existing) {
        $Current = [PSCustomObject]@{ deployed = $false; drift = @() }
        $Current | Add-Member -NotePropertyName 'templateBody' -NotePropertyValue $Template
        $Current | Add-Member -NotePropertyName 'existingContact' -NotePropertyValue $null
        return @{
            Expected = [PSCustomObject]@{ deployed = $true; drift = @() }
            Current  = $Current
        }
    }

    $FieldMap = @(
        @{ Template = 'email'; Current = "$($Existing.ExternalEmailAddress)"; IsEmail = $true }
        @{ Template = 'firstName'; Current = "$($Existing.FirstName)" }
        @{ Template = 'lastName'; Current = "$($Existing.LastName)" }
        @{ Template = 'mailTip'; Current = "$($Existing.MailTip)" }
        @{ Template = 'hidefromGAL'; Current = $Existing.HiddenFromAddressListsEnabled; IsBool = $true }
        @{ Template = 'companyName'; Current = "$($Existing.Company)" }
        @{ Template = 'state'; Current = "$($Existing.StateOrProvince)" }
        @{ Template = 'streetAddress'; Current = "$($Existing.StreetAddress)" }
        @{ Template = 'businessPhone'; Current = "$($Existing.Phone)" }
        @{ Template = 'website'; Current = "$($Existing.WebPage)" }
        @{ Template = 'jobTitle'; Current = "$($Existing.Title)" }
        @{ Template = 'city'; Current = "$($Existing.City)" }
        @{ Template = 'postalCode'; Current = "$($Existing.PostalCode)" }
        @{ Template = 'country'; Current = "$($Existing.CountryOrRegion)"; IsCountry = $true }
        @{ Template = 'mobilePhone'; Current = "$($Existing.MobilePhone)" }
    )
    $Differences = [System.Collections.Generic.List[string]]::new()
    foreach ($Field in $FieldMap) {
        $TemplateValue = $Template.($Field.Template)
        if ($Field.IsBool) {
            if ([bool]$TemplateValue -ne [bool]$Field.Current) { $Differences.Add($Field.Template) }
            continue
        }
        if ([string]::IsNullOrWhiteSpace("$TemplateValue")) { continue }
        # country: template stores an ISO code ('US'), Exchange returns the full name
        # ('United States'); normalise both to a code before comparing.
        $Mismatch = if ($Field.IsCountry) {
            [string]::IsNullOrWhiteSpace($Field.Current) -or (ConvertTo-CIPPCountryCode "$TemplateValue") -ne (ConvertTo-CIPPCountryCode $Field.Current)
        } elseif ($Field.IsEmail) {
            [string]::IsNullOrWhiteSpace($Field.Current) -or -not "$TemplateValue".Equals($Field.Current, [System.StringComparison]::OrdinalIgnoreCase)
        } else {
            [string]::IsNullOrWhiteSpace($Field.Current) -or "$TemplateValue" -ne $Field.Current
        }
        if ($Mismatch) { $Differences.Add($Field.Template) }
    }

    $Current = [PSCustomObject]@{ deployed = $true; drift = @($Differences) }
    # Carried for the executor, not graded.
    $Current | Add-Member -NotePropertyName 'templateBody' -NotePropertyValue $Template
    $Current | Add-Member -NotePropertyName 'existingContact' -NotePropertyValue $Existing

    @{
        Expected = [PSCustomObject]@{ deployed = $true; drift = @() }
        Current  = $Current
    }
}
