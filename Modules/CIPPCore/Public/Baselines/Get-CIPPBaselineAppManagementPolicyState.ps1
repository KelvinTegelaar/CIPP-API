function Get-CIPPBaselineAppManagementPolicyState {
    <#
    .SYNOPSIS
        Prepare hook for AppManagementPolicy: credential restrictions on the default app
        management policy.
    .DESCRIPTION
        Builds the desired restriction arrays the way the classic did, and the construction
        is why this is a hook: the operator's day counts become ISO durations (P30D), the
        password-addition state is MIRRORED onto symmetric key addition, and only configured
        settings contribute entries. Both sides sort by restrictionType and the application
        restrictions mirror onto service principal restrictions, exactly as the classic
        compared them.

        Nothing configured means the standard expresses no opinion - the classic returned
        without grading, and No Data is the honest equivalent.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $V = $Item.Variables
    $PasswordAddition = "$($V.passwordCredentialsPasswordAddition.value ?? $V.passwordCredentialsPasswordAddition)"
    $CustomPassword = "$($V.passwordCredentialsCustomPasswordAddition.value ?? $V.passwordCredentialsCustomPasswordAddition)"
    $PasswordLifetimeDays = "$($V.passwordCredentialsMaxLifetime)"
    $KeyLifetimeDays = "$($V.keyCredentialsMaxLifetime)"

    $PasswordCredentials = [System.Collections.Generic.List[object]]::new()
    if (-not [string]::IsNullOrWhiteSpace($PasswordAddition)) {
        foreach ($Type in @('passwordAddition', 'symmetricKeyAddition')) {
            $PasswordCredentials.Add([PSCustomObject]@{ restrictionType = $Type; state = $PasswordAddition; maxLifetime = $null; restrictForAppsCreatedAfterDateTime = '0001-01-01T00:00:00Z' })
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($CustomPassword)) {
        $PasswordCredentials.Add([PSCustomObject]@{ restrictionType = 'customPasswordAddition'; state = $CustomPassword; maxLifetime = $null; restrictForAppsCreatedAfterDateTime = '0001-01-01T00:00:00Z' })
    }
    if (-not [string]::IsNullOrWhiteSpace($PasswordLifetimeDays)) {
        $PasswordCredentials.Add([PSCustomObject]@{ restrictionType = 'passwordLifetime'; state = 'enabled'; maxLifetime = "P$($PasswordLifetimeDays)D"; restrictForAppsCreatedAfterDateTime = '0001-01-01T00:00:00Z' })
    }
    if (-not [string]::IsNullOrWhiteSpace($KeyLifetimeDays)) {
        $PasswordCredentials.Add([PSCustomObject]@{ restrictionType = 'symmetricKeyLifetime'; state = 'enabled'; maxLifetime = "P$($KeyLifetimeDays)D"; restrictForAppsCreatedAfterDateTime = '0001-01-01T00:00:00Z' })
    }
    $KeyCredentials = @(if (-not [string]::IsNullOrWhiteSpace($KeyLifetimeDays)) {
            [PSCustomObject]@{ restrictionType = 'asymmetricKeyLifetime'; state = 'enabled'; maxLifetime = "P$($KeyLifetimeDays)D"; restrictForAppsCreatedAfterDateTime = '0001-01-01T00:00:00Z' }
        })

    if ($PasswordCredentials.Count -eq 0 -and @($KeyCredentials).Count -eq 0) { return @{ Current = $null } }

    $SortedPassword = @($PasswordCredentials | Sort-Object { $_.restrictionType })
    $SortedKey = @($KeyCredentials | Sort-Object { $_.restrictionType })
    $Expected = [PSCustomObject]@{
        isEnabled                    = $true
        applicationRestrictions      = [PSCustomObject]@{ passwordCredentials = $SortedPassword; keyCredentials = $SortedKey }
        servicePrincipalRestrictions = [PSCustomObject]@{ passwordCredentials = $SortedPassword; keyCredentials = $SortedKey }
    }

    $Policy = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'DefaultAppManagementPolicy') | Select-Object -First 1
    if (-not $Policy) { return @{ Current = $null } }

    $Current = [PSCustomObject]@{
        isEnabled                    = [bool]$Policy.isEnabled
        applicationRestrictions      = [PSCustomObject]@{
            passwordCredentials = @($Policy.applicationRestrictions.passwordCredentials | Sort-Object -Property restrictionType)
            keyCredentials      = @($Policy.applicationRestrictions.keyCredentials | Sort-Object -Property restrictionType)
        }
        servicePrincipalRestrictions = [PSCustomObject]@{
            passwordCredentials = @($Policy.servicePrincipalRestrictions.passwordCredentials | Sort-Object -Property restrictionType)
            keyCredentials      = @($Policy.servicePrincipalRestrictions.keyCredentials | Sort-Object -Property restrictionType)
        }
    }
    # Carried for the executor: the PATCH body is the graded expected state itself -
    # carried BEFORE the round-trip below so the wire body keeps its exact strings.
    $Current | Add-Member -NotePropertyName 'desiredState' -NotePropertyValue $Expected

    # JSON round-trip the expected side so its ISO date strings become [datetime] the same
    # way the cached current side's did - ConvertFrom-Json converts ISO strings to real
    # datetimes, and the type-strict compare would otherwise report drift between two
    # values that PRINT identically.
    $Expected = $Expected | ConvertTo-Json -Depth 20 | ConvertFrom-Json

    @{ Expected = $Expected; Current = $Current }
}
