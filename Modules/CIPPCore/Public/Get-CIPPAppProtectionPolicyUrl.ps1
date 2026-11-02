function Get-CIPPAppProtectionPolicyUrl {
    <#
    .SYNOPSIS
        Resolves the deviceAppManagement collection an App Protection policy belongs to.

    .DESCRIPTION
        'AppProtection' is a single CIPP template type covering several concrete Graph types, each
        of which lives in its own collection, so a template cannot be deployed until the concrete
        type is known.

        @odata.type answers that directly, but Graph only emits it when the policy was read through
        the polymorphic managedAppPolicies collection. Read through its own collection - which is
        how CIPP captures these once the type is known - Graph omits @odata.type and records the
        type in @odata.context instead, so templates captured that way, and every copy synced from
        them, carry only the context. Fall back to it, and then to settings that exist on only one
        platform, before giving up.

        Returns $null when the policy identifies no platform at all.

    .PARAMETER Policy
        The policy payload, either as an object or as its raw JSON.

    .EXAMPLE
        Get-CIPPAppProtectionPolicyUrl -Policy ($RawJSON | ConvertFrom-Json)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        $Policy
    )

    if ($Policy -is [string]) {
        try {
            $Policy = $Policy | ConvertFrom-Json -ErrorAction Stop
        } catch {
            return $null
        }
    }
    if (-not $Policy) { return $null }

    # Graph's collection names are not a plain pluralisation of the type name, so map the types App
    # Protection can hold and keep the -y/-ies rule only as a fallback for anything added later.
    $CollectionByType = @{
        'iosManagedAppProtection'               = 'iosManagedAppProtections'
        'androidManagedAppProtection'           = 'androidManagedAppProtections'
        'windowsManagedAppProtection'           = 'windowsManagedAppProtections'
        'defaultManagedAppProtection'           = 'defaultManagedAppProtections'
        'targetedManagedAppConfiguration'       = 'targetedManagedAppConfigurations'
        'windowsInformationProtectionPolicy'    = 'windowsInformationProtectionPolicies'
        'mdmWindowsInformationProtectionPolicy' = 'mdmWindowsInformationProtectionPolicies'
    }

    $ToCollection = {
        param($Type)
        $Type = "$Type" -replace '^#', '' -replace '^microsoft\.graph\.', ''
        if ([string]::IsNullOrWhiteSpace($Type)) { return $null }
        if ($CollectionByType.ContainsKey($Type)) { return $CollectionByType[$Type] }
        if ($Type.EndsWith('y')) { return ($Type -replace 'y$', 'ies') }
        return "$($Type)s"
    }

    $Collection = & $ToCollection $Policy.'@odata.type'
    if ($Collection) { return $Collection }

    # .../$metadata#deviceAppManagement/<collection>[/microsoft.graph.<type>]/$entity
    if ("$($Policy.'@odata.context')" -match '#deviceAppManagement/(?<collection>[A-Za-z0-9]+)(/microsoft\.graph\.(?<type>[A-Za-z0-9]+))?') {
        if ($Matches.type) {
            return (& $ToCollection $Matches.type)
        }
        # managedAppPolicies is the polymorphic collection: it names no platform and cannot be
        # posted to, so a context pointing at it says nothing about the type.
        if ($Matches.collection -ne 'managedAppPolicies') {
            return $Matches.collection
        }
    }

    # Nothing authoritative left. Settings that exist on one platform only still identify the two
    # types that make up nearly every App Protection policy. Require the match to be one-sided -
    # deploying into the wrong collection is worse than reporting that the type is unknown.
    $IosOnlySettings = @(
        'faceIdBlocked'
        'appDataEncryptionType'
        'thirdPartyKeyboardsBlocked'
        'filterOpenInToOnlyManagedApps'
        'managedUniversalLinks'
        'exemptedUniversalLinks'
        'exemptedAppProtocols'
        'allowedIosDeviceModels'
        'appActionIfIosDeviceModelNotAllowed'
        'protectInboundDataFromUnknownSources'
    )
    $AndroidOnlySettings = @(
        'screenCaptureBlocked'
        'encryptAppData'
        'disableAppEncryptionIfDeviceEncryptionIsEnabled'
        'exemptedAppPackages'
        'approvedKeyboards'
        'allowedAndroidDeviceManufacturers'
        'appActionIfAndroidDeviceManufacturerNotAllowed'
        'allowedAndroidDeviceModels'
        'appActionIfAndroidDeviceModelNotAllowed'
        'customBrowserPackageId'
    )

    $PropertyNames = @($Policy.PSObject.Properties.Name)
    $IosMatches = @($IosOnlySettings | Where-Object { $PropertyNames -contains $_ }).Count
    $AndroidMatches = @($AndroidOnlySettings | Where-Object { $PropertyNames -contains $_ }).Count

    if ($IosMatches -gt 0 -and $AndroidMatches -eq 0) { return 'iosManagedAppProtections' }
    if ($AndroidMatches -gt 0 -and $IosMatches -eq 0) { return 'androidManagedAppProtections' }

    return $null
}
