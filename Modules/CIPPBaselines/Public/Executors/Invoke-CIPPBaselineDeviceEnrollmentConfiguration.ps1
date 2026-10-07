function Invoke-CIPPBaselineDeviceEnrollmentConfiguration {
    <#
    .SYNOPSIS
        DeviceEnrollmentConfiguration executor: PATCHes one enrollment configuration by the id
        its prepare hook discovered.
    .DESCRIPTION
        Every configuration in this family lives at
        deviceManagement/deviceEnrollmentConfigurations/{id}, and the id is per tenant - it
        carries the Intune account GUID as a prefix, so no token can render it and no static
        uri can address it. The prepare hook has already found the right row while reading the
        cache, and passes it on -Current as configurationId. Nothing is re-resolved here: a
        second lookup could pick a different row than the one the compare graded.

        Writes are DELEGATED by default, matching every standard in this family - the classic
        code either omitted -AsApp or set it to $false explicitly. A definition can override
        per write with asApp, but none currently needs to.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $ConfigurationId = "$($Current.configurationId)"
    if ([string]::IsNullOrWhiteSpace($ConfigurationId)) {
        throw 'DeviceEnrollmentConfiguration: the prepare hook found no configuration to write to on this tenant.'
    }
    if (@(($Remediate.body ?? [PSCustomObject]@{}).PSObject.Properties).Count -eq 0) {
        throw 'DeviceEnrollmentConfiguration: nothing configured to write.'
    }
    # Hook-computed write values ride in on -Current next to configurationId: the ESP's
    # blockDeviceSetupRetryByUser is the INVERSE of the operator's BlockDevice switch,
    # which no %token% can render. Without it the PATCH fixes every property except
    # this one and its drift flaps forever.
    if ($null -ne $Current.blockDeviceSetupRetryByUserDesired) {
        $Remediate.body | Add-Member -NotePropertyName 'blockDeviceSetupRetryByUser' -NotePropertyValue ([bool]$Current.blockDeviceSetupRetryByUserDesired) -Force
    }

    $null = New-GraphPostRequest -tenantid $TenantFilter `
        -uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations/$ConfigurationId" `
        -Type PATCH `
        -Body (ConvertTo-Json -Compress -Depth 20 -InputObject $Remediate.body) `
        -ContentType 'application/json; charset=utf-8' `
        -AsApp ([bool]($Remediate.asApp -eq $true))
}
