function New-CIPPCAWhatIfRequest {
    <#
    .SYNOPSIS
        Builds the request body for the Conditional Access What If evaluation API.
    .DESCRIPTION
        The identity is a user (UserId) or a single-tenant service principal (ServicePrincipalId).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $UserId,
        $ServicePrincipalId,
        $IncludeApplications,
        $Conditions,
        [switch]$AppliedPoliciesOnly
    )

    if (-not $UserId -and -not $ServicePrincipalId) {
        throw 'A What If evaluation needs a UserId or a ServicePrincipalId.'
    }

    $Identity = if ($ServicePrincipalId) {
        @{ '@odata.type' = '#microsoft.graph.servicePrincipalSignIn'; servicePrincipalId = "$ServicePrincipalId" }
    } else {
        @{ '@odata.type' = '#microsoft.graph.userSignIn'; userId = "$UserId" }
    }

    $Applications = @($IncludeApplications | Where-Object { $_ } | ForEach-Object { "$($_.value ?? $_)" })
    if ($Applications.Count -eq 0) {
        $Applications = @('00000002-0000-0ff1-ce00-000000000000')
    }

    if ($Conditions -is [System.Collections.IDictionary]) { $Conditions = [PSCustomObject]$Conditions }
    $SignInConditions = @{}
    foreach ($Property in @(($Conditions ?? [PSCustomObject]@{}).PSObject.Properties)) {
        $Value = $Property.Value
        if ($null -eq $Value -or "$Value" -eq '') { continue }
        if ($Value -is [System.Management.Automation.PSCustomObject] -and $Value.PSObject.Properties['value'] -and $Value.PSObject.Properties['label']) {
            $Value = $Value.value
        }
        if ($Property.Name -eq 'authenticationFlow' -and $Value -is [string]) {
            $Value = @{ transferMethod = $Value }
        }
        if ($Property.Name -eq 'deviceInfo') {
            $Allowed = @('deviceId', 'displayName', 'enrollmentProfileName', 'extensionAttributes', 'isCompliant', 'manufacturer', 'mfaRegistered', 'model', 'operatingSystem', 'operatingSystemVersion', 'ownership', 'physicalIds', 'profileType', 'systemLabels', 'trustType')
            $Device = @{}
            if ($Value -is [System.Collections.IDictionary]) { $Value = [PSCustomObject]$Value }
            foreach ($DeviceProperty in @(($Value ?? [PSCustomObject]@{}).PSObject.Properties)) {
                if ($Allowed -contains $DeviceProperty.Name -and $null -ne $DeviceProperty.Value) { $Device[$DeviceProperty.Name] = $DeviceProperty.Value }
            }
            if ($Device.Count -eq 0) { continue }
            $Value = $Device
        }
        $SignInConditions[$Property.Name] = $Value
    }

    $Body = @{
        signInIdentity   = $Identity
        signInContext    = @{
            '@odata.type'       = '#microsoft.graph.applicationContext'
            includeApplications = $Applications
        }
        signInConditions = $SignInConditions
    }
    if ($AppliedPoliciesOnly) { $Body.appliedPoliciesOnly = $true }
    $Body
}
