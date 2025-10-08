function Invoke-CIPPStandardDisableSelfServiceLicenses {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableSelfServiceLicenses
    .SYNOPSIS
        (Label) Disable Self Service Licensing
    .DESCRIPTION
        (Helptext) Note: requires 'Billing Administrator' GDAP role. This standard disables all self service licenses and enables all exclusions
        (DocsDescription) Note: requires 'Billing Administrator' GDAP role. This standard disables all self service licenses and enables all exclusions
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        EXECUTIVETEXT
            Prevents employees from purchasing Microsoft 365 licenses independently, ensuring all software acquisitions go through proper procurement channels. This maintains budget control, prevents unauthorized spending, and ensures compliance with corporate licensing agreements.
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.DisableSelfServiceLicenses.Exclusions","label":"License Ids to exclude from this standard","required":false}
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
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DisableSelfServiceLicenses'

    try {
        $selfServiceItems = (New-GraphGETRequest -scope 'aeb86249-8ea3-49e2-900b-54cc8e308f85/.default' -uri 'https://licensing.m365.microsoft.com/v1.0/policies/AllowSelfServicePurchase/products' -tenantid $Tenant).items
    } catch {
        if ($_.Exception.Message -like '*403*') {
            $Message = "Failed to retrieve self service products: Insufficient permissions. Please ensure the tenant GDAP relationship includes the 'Billing Administrator' role: $($_.Exception.Message)"
        }
        else {
            $Message = "Failed to retrieve self service products: $($_.Exception.Message)"
        }
        Write-LogMessage -API 'Standards' -tenant $tenant -message $Message -sev Error
        throw $Message
    }

    if ($settings.remediate) {
        if ($settings.exclusions -like '*;*') {
            $exclusions = $settings.Exclusions -split (';')
        } else {
            $exclusions = $settings.Exclusions -split (',')
        }

        $selfServiceItems | ForEach-Object {
            $body = $null

            if ($_.policyValue -eq 'Enabled' -AND ($_.productId -in $exclusions)) {
                # Self service is enabled on product and productId is in exclusions, skip
            }
            if ($_.policyValue -eq 'Disabled' -AND ($_.productId -in $exclusions)) {
                # Self service is disabled on product and productId is in exclusions, enable
                $body = '{ "policyValue": "Enabled" }'
            }
            if ($_.policyValue -eq 'Enabled' -AND ($_.productId -notin $exclusions)) {
                # Self service is enabled on product and productId is NOT in exclusions, disable
                $body = '{ "policyValue": "Disabled" }'
            }
            if ($_.policyValue -eq 'Disabled' -AND ($_.productId -notin $exclusions)) {
                # Self service is disabled on product and productId is NOT in exclusions, skip
            }

            try {
                if ($body) {
                    $product = $_
                    New-GraphPOSTRequest -scope 'aeb86249-8ea3-49e2-900b-54cc8e308f85/.default' -uri "https://licensing.m365.microsoft.com/v1.0/policies/AllowSelfServicePurchase/products/$($product.productId)" -tenantid $Tenant -body $body -type PUT
                }
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set product status for $($product.productId) with body $($body) for reason: $($_.Exception.Message)" -sev Error
                #Write-Error "Failed to disable product $($product.productName):$($_.Exception.Message)"
            }
        }

        if (!$exclusions) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No exclusions set for self-service licenses, disabled all not excluded licenses for self-service.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Exclusions present for self-service licenses, disabled all not excluded licenses for self-service.' -sev Info
        }
    }

    if ($Settings.alert) {
        $selfServiceItemsToAlert = $selfServiceItems | Where-Object { $_.policyValue -eq 'Enabled' }
        if (!$selfServiceItemsToAlert) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'All self-service licenses are disabled' -sev Info
        } else {
            Write-StandardsAlert -message "One or more self-service licenses are enabled" -object $selfServiceItemsToAlert -tenant $tenant -standardName 'DisableSelfServiceLicenses' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'One or more self-service licenses are enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        #Add-CIPPBPAField -FieldName '????' -FieldValue "????" -StoreAs bool -Tenant $tenant
    }
}
