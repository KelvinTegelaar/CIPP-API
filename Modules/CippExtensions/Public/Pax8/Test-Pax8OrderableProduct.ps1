function Test-Pax8OrderableProduct {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProductId
    )

    $Dependencies = Invoke-Pax8Request -Method GET -Path "products/$ProductId/dependencies"
    $DependencyItems = if ($Dependencies.content) { @($Dependencies.content) } elseif ($Dependencies -is [array]) { @($Dependencies) } else { @() }
    if ($DependencyItems.Count -gt 0) {
        throw 'This Pax8 product has dependencies and cannot be ordered from CIPP yet.'
    }

    $ProvisionDetails = Invoke-Pax8Request -Method GET -Path "products/$ProductId/provision-details"
    $ProvisionItems = if ($ProvisionDetails.content) { @($ProvisionDetails.content) } elseif ($ProvisionDetails -is [array]) { @($ProvisionDetails) } else { @() }
    $RequiredProvisionItems = @($ProvisionItems | Where-Object { $_.required -eq $true -or $_.isRequired -eq $true })
    if ($RequiredProvisionItems.Count -gt 0) {
        throw 'This Pax8 product requires provisioning details and cannot be ordered from CIPP yet.'
    }

    return $true
}
