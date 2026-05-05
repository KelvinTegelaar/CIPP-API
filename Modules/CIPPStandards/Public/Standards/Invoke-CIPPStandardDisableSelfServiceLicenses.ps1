function Invoke-CIPPStandardDisableSelfServiceLicenses {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableSelfServiceLicenses
    .SYNOPSIS
        (Label) Disable Self Service Licensing
    .DESCRIPTION
        (Helptext) **Requires 'Billing Administrator' GDAP role.** This standard disables all self service licenses and enables all exclusions
        (DocsDescription) \*\*Requires 'Billing Administrator' GDAP role.\*\* This standard disables all self service licenses and enables all exclusions
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        EXECUTIVETEXT
            Prevents employees from purchasing Microsoft 365 licenses independently, ensuring all software acquisitions go through proper procurement channels. This maintains budget control, prevents unauthorized spending, and ensures compliance with corporate licensing agreements.
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.DisableSelfServiceLicenses.Exclusions","label":"License Ids to exclude from this standard","required":false}
            {"type":"switch","name":"standards.DisableSelfServiceLicenses.DisableTrials","label":"Disable starting trials on behalf of your organization"}
        IMPACT
            Medium Impact
        ADDEDDATE
            2021-11-16
        POWERSHELLEQUIVALENT
            Set-MsolCompanySettings -AllowAdHocSubscriptions \$false
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    try {
        $selfServiceItems = (New-GraphGETRequest -scope 'aeb86249-8ea3-49e2-900b-54cc8e308f85/.default' -uri 'https://licensing.m365.microsoft.com/v1.0/policies/AllowSelfServicePurchase/products' -tenantid $Tenant).items
    } catch {
        if ($_.Exception.Message -like '*403*') {
            $Message = "Failed to retrieve self service products: Insufficient permissions. Please ensure the tenant GDAP relationship includes the 'Billing Administrator' role: $($_.Exception.Message)"
        } else {
            $Message = "Failed to retrieve self service products: $($_.Exception.Message)"
        }
        Write-LogMessage -API 'Standards' -tenant $tenant -message $Message -sev Error
        throw $Message
    }

    if ($settings.exclusions -like '*;*') {
        $exclusions = $settings.Exclusions -split (';')
    } else {
        $exclusions = $settings.Exclusions -split (',')
    }

    $CurrentValues = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($Item in $selfServiceItems) {
        $CurrentValues.Add([PSCustomObject]@{
                productName = $Item.productName
                productId   = $Item.productId
                policyValue = $Item.policyValue
            })
    }

    try {
        $AuthPolicy = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/policies/authorizationPolicy' -tenantid $Tenant
        $AllowEmailSubscriptions = if ($AuthPolicy.allowedToSignUpEmailBasedSubscriptions) { 'Enabled' } else { 'Disabled' }
        $CurrentValues.Add([PSCustomObject]@{
                productName = 'Email Based Subscriptions'
                productId   = 'allowedToSignUpEmailBasedSubscriptions'
                policyValue = $AllowEmailSubscriptions
            })
    } catch {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to retrieve authorization policy: $($_.Exception.Message)" -sev Error
    }

    if ($Settings.DisableTrials) {
        try {
            $AutoClaimPolicy = New-GraphGetRequest -scope 'https://admin.microsoft.com/.default' -TenantID $Tenant -Uri 'https://admin.microsoft.com/fd/m365licensing/v1/policies/autoclaim'
            $CurrentValues.Add([PSCustomObject]@{
                    productName = 'Trial Autoclaim'
                    productId   = 'autoclaim'
                    policyValue = if ($null -eq $AutoClaimPolicy.policyValue) { 'Disabled' } else { $AutoClaimPolicy.policyValue }
                })
        } catch {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to retrieve trial autoclaim policy: $($_.Exception.Message)" -sev Error
        }
    }

    $ExpectedValues = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($Item in $selfServiceItems) {

        if ($Item.productId -in $exclusions) {
            $desiredPolicyValue = 'Enabled'
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Exclusion present for self-service license '$($Item.productName) - $($Item.productId)'"
        } else {
            $desiredPolicyValue = 'Disabled'
        }

        $ExpectedValues.Add([PSCustomObject]@{
                productName = $Item.productName
                productId   = $Item.productId
                policyValue = $desiredPolicyValue
            })
    }

    if ($Settings.DisableTrials) {
        $ExpectedValues.Add([PSCustomObject]@{
                productName = 'Trial Autoclaim'
                productId   = 'autoclaim'
                policyValue = 'Disabled'
            })
    }

    $ExpectedValues.Add([PSCustomObject]@{
            productName = 'Email Based Subscriptions'
            productId   = 'allowedToSignUpEmailBasedSubscriptions'
            policyValue = 'Disabled'
        })

    if ($settings.remediate) {

        $Compare = Compare-Object -ReferenceObject $ExpectedValues -DifferenceObject $CurrentValues -Property productName, productId, policyValue

        if (!$Compare) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'self service licenses are already set correctly.' -sev Info
        } else {

            $NeedsUpdate = $Compare | Where-Object { $_.SideIndicator -eq '<=' }

            foreach ($Item in $NeedsUpdate) {
                try {

                    $currentItem = $CurrentValues | Where-Object { $_.productId -eq $Item.productId } | Select-Object -First 1
                    $currentValue = if ($currentItem) { $currentItem.policyValue } else { '<unknown>' }

                    $body = @{ policyValue = $Item.policyValue } | ConvertTo-Json -Compress

                    if ($Item.productId -eq 'autoclaim') {
                        New-GraphPostRequest -scope 'https://admin.microsoft.com/.default' -TenantID $Tenant -Uri 'https://admin.microsoft.com/fd/m365licensing/v1/policies/autoclaim' -Body $body
                    } elseif ($Item.productId -eq 'allowedToSignUpEmailBasedSubscriptions') {
                        $authBody = @{ allowedToSignUpEmailBasedSubscriptions = $false } | ConvertTo-Json -Compress
                        New-GraphPostRequest -uri 'https://graph.microsoft.com/v1.0/policies/authorizationPolicy' -tenantid $Tenant -body $authBody -type PATCH
                    } else {
                        New-GraphPOSTRequest -scope 'aeb86249-8ea3-49e2-900b-54cc8e308f85/.default' -uri "https://licensing.m365.microsoft.com/v1.0/policies/AllowSelfServicePurchase/products/$($Item.productId)" -tenantid $Tenant -body $body -type PUT
                    }

                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Changed Self Service status for product '$($Item.productName) - $($Item.productId)' from '$currentValue' to '$($Item.policyValue)'" -sev Info
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set product status for '$($Item.productName) - $($Item.productId)' with body $($body) for reason: $($_.Exception.Message)" -sev Error
                }
            }
        }

        $CurrentValues = [System.Collections.Generic.List[PSCustomObject]]::new()
        $refreshedItems = (New-GraphGETRequest -scope 'aeb86249-8ea3-49e2-900b-54cc8e308f85/.default' -uri 'https://licensing.m365.microsoft.com/v1.0/policies/AllowSelfServicePurchase/products' -tenantid $Tenant).items
        foreach ($Item in $refreshedItems) {
            $CurrentValues.Add([PSCustomObject]@{
                    productName = $Item.productName
                    productId   = $Item.productId
                    policyValue = $Item.policyValue
                })
        }
        try {
            $AuthPolicy = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/policies/authorizationPolicy' -tenantid $Tenant
            $AllowEmailSubscriptions = if ($AuthPolicy.allowedToSignUpEmailBasedSubscriptions) { 'Enabled' } else { 'Disabled' }
            $CurrentValues.Add([PSCustomObject]@{
                    productName = 'Email Based Subscriptions'
                    productId   = 'allowedToSignUpEmailBasedSubscriptions'
                    policyValue = $AllowEmailSubscriptions
                })
        } catch {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to retrieve authorization policy after remediation: $($_.Exception.Message)" -sev Error
        }

        if ($Settings.DisableTrials) {
            try {
                $AutoClaimPolicy = New-GraphGetRequest -scope 'https://admin.microsoft.com/.default' -TenantID $Tenant -Uri 'https://admin.microsoft.com/fd/m365licensing/v1/policies/autoclaim'
                $CurrentValues.Add([PSCustomObject]@{
                        productName = 'Trial Autoclaim'
                        productId   = 'autoclaim'
                        policyValue = if ($null -eq $AutoClaimPolicy.policyValue) { 'Disabled' } else { $AutoClaimPolicy.policyValue }
                    })
            } catch {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to retrieve trial autoclaim policy after remediation: $($_.Exception.Message)" -sev Error
            }
        }
    }

    if ($Settings.alert) {
        $selfServiceItemsToAlert = $CurrentValues | Where-Object { $_.policyValue -eq 'Enabled' }
        if (!$selfServiceItemsToAlert) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'All self-service licenses are disabled' -sev Info
        } else {
            Write-StandardsAlert -message 'One or more self-service licenses are enabled' -object $selfServiceItemsToAlert -tenant $tenant -standardName 'DisableSelfServiceLicenses' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'One or more self-service licenses are enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {

        $StateIsCorrect = !(Compare-Object -ReferenceObject $ExpectedValues -DifferenceObject $CurrentValues -Property productName, productId, policyValue)

        $ExpectedValuesHash = @{}
        foreach ($Item in $ExpectedValues) {
            $ExpectedValuesHash[$Item.productName] = [PSCustomObject]@{
                Id    = $Item.productId
                Value = $Item.policyValue
            }
        }
        $ExpectedValue = [PSCustomObject]$ExpectedValuesHash

        $CurrentValuesHash = @{}
        foreach ($Item in $CurrentValues) {
            $CurrentValuesHash[$Item.productName] = [PSCustomObject]@{
                Id    = $Item.productId
                Value = $Item.policyValue
            }
        }
        $CurrentValue = [PSCustomObject]$CurrentValuesHash

        Set-CIPPStandardsCompareField -FieldName 'standards.DisableSelfServiceLicenses' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableSelfServiceLicenses' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
